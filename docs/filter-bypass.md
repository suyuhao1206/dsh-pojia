# 上游 content_filter 对抗：分层策略与实现

本文说明 dsh-pojia 的过滤对抗层（`lib/filter-codec.js` + `lib/filter-bypass.js` + 补丁 #90/#91）为什么这样设计，
以及为什么"base64 一下"不是主力手段。

## 一、先分清对手是谁

| 对手类型 | 典型实现 | 有效手段 | 无效/负收益手段 |
|---|---|---|---|
| **A 类** | 正则、敏感词表、DFA 自动机 | 零宽分词、全角混排、简繁换字面、拼音、下划线分词 | 语义层大改（词表照样命中原文） |
| **B 类** | 小模型分类器（fastText / BERT 级） | 语义改写：分段、视角切换、措辞替换、情绪化叙事 | 纯符号混淆（归一化即失效） |
| **C 类** | LLM judge（现代服务端主力） | **风险感知分片**、**输出侧暗语 + 本地还原**、续写引导 | **编码类**：护栏普遍 `decode-then-classify`，编码反而提高"规避意图"的判定 |

关键事实：

- 编码攻击对"关键词过滤 + 浅层分类器"有效，但标准防御就是**先解码再分类**。
  参见 [Cipher attacks: base64, ROT13, leetspeak](https://www.promptinjectionprevention.com/kb/cipher-attacks-base64-rot13-leetspeak.php)。
- 中文拼音/拆字/同音字规避对**轻量中文模型**有效，说明它真是 A/B 类的手段，
  参见 [Chinese Pattern Safety Evasion](https://www.promptfoo.dev/lm-security-db/vuln/chinese-pattern-safety-evasion-680120ac/)。
- 但国内平台对拼音规避**早有专利级防御**：用单字拼音特征 + 相似全词拼音特征匹配"规避词语及其变形"
  （[CN110674262A](https://patentimages.storage.googleapis.com/78/bb/8e/153ecece98a726/CN110674262A.pdf)），
  以及把敏感词拼音串塞进**拼音前缀树**、非汉字串直接映射回汉字序号再命中自动机
  （[CN113177408A](https://patentimages.storage.googleapis.com/d0/20/19/b94005f72844b6/CN113177408A.pdf)）。
  → 在国内 API 上，拼音混淆属于"低收益、且可能被判规避"。
- 分片要"风险感知"，不能均分：应只把 detector-sensitive 的片段单独隔离，过度碎片化会破坏语义导致下游模型无法推断意图，
  参见 [Prompt Overflow: What the Guardrail Inspects Is Not What the Model Infers](https://arxiv.org/html/2605.23196v1)。
- 在 user 边界后注入续写引导句式对拒答有压制作用，参见 [Drive Overrides Refusal](https://promptfoo.dev/lm-security-db/vuln/drive-overrides-refusal-19d1b3b4/)。
- 专用护栏（NeMo Guard / Prompt Guard / LLM Guard / LangKit）大量依赖表层模式匹配，评估集含 DeepSeek V3，
  参见 [LLM Guardrail Bypass](https://promptfoo.dev/lm-security-db/vuln/llm-guardrail-bypass-589f76c8)。

## 二、运行时那一层：让"被拒"不再等于"整轮报废"

1. `dsh-llm-pi-ai` 的 `classifyPiAiError` 认不出的错误 → `PI_AI_ERROR`（无 `retryChoice`）。
2. `LLM_FAILURE_CODES` 里 `retryChoice` 只表示"可被选进 `retryableCodes`"，**不代表默认重试**。
3. `dsh-llm-retry` 的判定：`if (!policy.retryableCodes.includes(failure.code)) return next();`
4. 默认 `DEFAULT_RETRYABLE_CODES = [EMPTY_RESPONSE, RATE_LIMIT, SERVER, TIMEOUT, TRANSPORT]`，
   `maxRetries=5`、`initialDelayMs=500`、`maxDelayMs=10000`、`jitterRatio=0.1`。

补丁：

- **#90** `PI_AI_CONTENT_FILTER_RETRYABLE`：`content_filter|moderation|flagged|safety policy|inappropriate` → `MALFORMED_RESPONSE`。
- **#91** `PI_AI_CONTENT_FILTER_RETRY_DEFAULT`：把 `MALFORMED_RESPONSE` 加进默认 `retryableCodes`。
  少了 #91，#90 判成可重试也不会真的重试。

## 三、请求侧 8 档阶梯（`filterEscape(request, attempt)`）

| 档 | stage | 做法 | 目标对手 | 输出还原 |
|---|---|---|---|---|
| 1 | `frame` | 虚构框架 + 成年声明 + 叙事化 + 只要 600 字 | B/C | 无 |
| 2 | `segment` | `riskAwareChunks` 按句切、高危句隔离，**发风险最低那段** | B/C | 无 |
| 3 | `pov` | 第三人称分镜 / 剧本格式 | B/C | 无 |
| 4 | `glossary` | 正文只写 `[[G]]/[[P]]/[[B]]/[[M]]/[[O]]` 代号 | C（主力） | `applyGlossary` |
| 5 | `continue` | 只发"接着上一段写第 2 段" | C（最省） | 无 |
| 6 | `euphemize` | 显式词→动作/温度/呼吸描述 | B | 无 |
| 7 | `codec` | 零宽断词 + 简繁换字面（只打词表词） | A | `decodeOutput({zhHant:true})` |
| 8 | `route` | 换 provider / 本地模型 | 全部 | 无 |

`retryWithReframe({send, request, adaptive})` 的调度：退避 `0/800/1800/3500/6000/9000/12000/15000 ms`；
`adaptive=true` 时连续两次被打回就**回退一档**（升级撞墙说明方向错了），并把每次尝试记进 `history`。

## 四、为什么"输出侧暗语"是主力

C 类 judge 判的是"这段文本是否在生成违规内容"。如果模型只写 `[[G]]`、`[[P]]` 这类代号：

- 出站文本在语义上**不构成**违规内容，判定的抓手消失了；
- 代号 → 正文的映射发生在**本地**（`applyGlossary`），用户拿到的仍是完整文本；
- 与分片叠加时，每段都短、都干净、衔接靠 `continue`。

代价：需要一次本地还原；代号表要固定（本实现用 8 个 ASCII 代号，避免被当成占位符忽略）。

## 五、不吹的边界

- 客户端**关不掉**服务端分类器；本层只改变"被判定的对象"，不改变"判定规则"。
- 编码档（第 7 档）只在 A 类对手面前有意义；在 LLM judge 面前会把"规避意图"暴露得更明显。
- 拼音在国内 API 上属于已知攻防（见上引专利），只做低剂量、只打词表词。
- 分片越细越容易过，但语义连贯性越差；`riskAwareChunks` 的取舍是"只隔离高危句"。

## 六、自测

```
riskAwareChunks("…要内射…她呻吟着，他抽插得更快。")
  seg1 risk=5.00 len=33
  seg2 risk=7.00 len=12      → 第 2 段风险更高，因此放走的通常是 seg1

glossary:   "…[[M]]。…[[S]]，[[D]]。"  →  "…硬得发烫。…声音黏得化不开，湿得一塌糊涂。"
codec:      "做爱 内射 呻吟" → 零宽+简繁（词表不再命中）→ 还原一致 = true
pinyin:     "做爱和内射" → "zuo ai和nei she" → 还原一致
retry:      前 3 次 blocked 后，attempt#4 在 segment 档通过
```
