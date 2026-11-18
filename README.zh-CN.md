# dsh-pojia

DeepSeek Harness 破甲（jailbreak / 清洗）插件：让所有模型都能破甲，不同模型可换不同提示词。清洗 + 网络安全演练台二合一。

- **适配范围**：DeepSeek Harness **0.2.2-rc.3**（官方桌面 EXE），插件 **1.0.1** 及以上。更早的 dsh 用对应老版本。
- **本版本只维护桌面端。** 不含 Web 端（`dsh web`）部署说明。

---

## 部署（桌面端 · Windows）

**不需要 `dsh` 命令、不需要 Node、也不需要 pnpm。** 三种方式任选一种，装完插件**还不会改宿主**，必须再做「首次启用」三步。

### 方式一：双击安装器（推荐）

1. 解压本插件，双击 `install.cmd`。
2. 脚本自动完成三件事：同步插件到 `%USERPROFILE%\.dsh\plugins\dsh-pojia` → 在 `profiles\desktop\node_modules\dsh-pojia` 建链接指向它 → 往 profile 的 `package.json` 写 `dependencies` 与 `dsh.profile.bundles`（改前自动备份）。
3. 完全退出桌面端再重开 → 点会话标题旁的 **dsh-pojia** → **清洗** → **应用**。

可选参数（命令行里用，不传就是默认）：

```bat
install.cmd                       :: 先试宿主自带 CLI，失败退回手工接线
install.cmd -Mode link            :: 只手工接线（最快、最稳）
install.cmd -DryRun               :: 只打印要做什么，不落盘
install.cmd -Source "D:\code\dsh-pojia"   :: 指定插件目录
install.cmd -Uninstall            :: 从 profile 摘掉（插件文件保留）
install.cmd -Uninstall -Purge     :: 连 %USERPROFILE%\.dsh\plugins\dsh-pojia 一起删
install.cmd -ProfileName desktop  :: 换 profile
```

脚本用宿主自带的 `node.exe` 改 JSON；连它也没找到时会退回纯文本改写并重新解析校验，所以不需要你装任何运行环境。

### 方式二：宿主界面里装（零命令行）

桌面端 → 左侧 **插件** → **添加插件** → 填**本插件目录的绝对路径**（例：`D:\apps\dsh-pojia`）→ 安装 → 完全退出再重开。

### 方式三：已经启用 `dsh` 命令的话

```sh
cd <本目录>
dsh plugin --profile desktop add .
```

这条命令要求 `dsh` 已经在 PATH 里（多数桌面安装默认没有）。没有就走方式一或方式二。

### 方式四：手工接线（排障用）

1. 找到正在使用的 `$DSH_HOME`（本机为 `%USERPROFILE%\.dsh`，认 `profiles\` 目录存在）。
2. 把整个插件目录放到 `$DSH_HOME\plugins\dsh-pojia`（放别处也行，下面链接指过去）。
3. 在 `$DSH_HOME\profiles\desktop\node_modules\dsh-pojia` 建一个 junction / 目录链接，指向第 2 步的目录。
4. 编辑 `$DSH_HOME\profiles\desktop\package.json`：
   - `dependencies` 追加 `"dsh-pojia": "link:<插件目录，用正斜杠>"`
   - `dsh.profile.bundles` 末尾追加 `"dsh-pojia"`（不要写两次，JSON 保持合法）
5. **不需要 `pnpm install`**：链接已经能让宿主解析到插件。

旧版这里写的是「复制到 node_modules + pnpm install」，那条路对没装 pnpm 的用户是死路，已经换成链接写法。

### 从旧 dsh-purge 迁移

1. 先在旧插件侧栏点「卸载」（或聊天 `/purge uninstall`），还原宿主原文件。
2. 完全退出桌面端（托盘也退出），再按上面方式安装 `dsh-pojia`。

### 首次启用三步

1. **完全退出并重新打开**桌面端。
2. 点会话标题旁的 **dsh-pojia** → **清洗** → **应用**。
3. 应用成功会自动重启一次；重启后**新开一轮对话**，注入才进当前会话。

---

## 使用

### 聊天命令

```text
/pojia status | apply | revert | uninstall | edit | help
/rules list | use <id> | create <id> [别名] [目标] | delete <id> | reset | help
/skills list | import <压缩包或文件夹> | create <id> [说明] | delete <id> | help
/rewind once | round
```

### 模型工具

```text
pojia_status   pojia_apply   pojia_revert
```

### 命令行

```sh
dsh-pojia --status     # 显示状态
dsh-pojia --apply      # 应用全部清洗
dsh-pojia --revert     # 回滚还原
dsh-pojia --uninstall  # 卸载（先还原）
dsh-pojia --edit       # 编辑注入文件 prompt-inject.md
```

### 侧栏功能（会话标题旁的 dsh-pojia）

| 区域 | 说明 |
| --- | --- |
| 清洗 | 补丁分组查看与应用、提示词编辑、规则集、Skill、自己的服务器 |
| 提示词 | 编辑 `prompt-inject.md`，每轮必注入的覆盖段，优先级最高 |
| 规则集 | 多套 AGENTS.md / CLAUDE.md，启用写入 `$DSH_HOME`；本地工作区规则按 `strict / fallback / always` 策略参与注入 |
| Skill | 导入 zip / 文件夹到官方技能目录 `$DSH_HOME\skills\<id>\SKILL.md`，命中与 `/名称` 由 DSH 加载 |
| 自己的服务器 | 登记你自己的服务器（写 `$DSH_HOME\net-scope-allow.txt`），用于放开网络围栏 |
| 演练台 | 授权后的红队演练台：红队模式预设（五角色流水线）、SQLite 资产库、17 个随包技能、环境适配、演练报告 |

### 演练台授权与围栏

- 第一次进演练台：读完整声明 → 倒计时 → 滚到文末 → 勾满三项 → 确认授权。授权记录在 `$DSH_HOME\dsh-purge\drill-grant.json`。
- 网络：默认禁止大陆/港澳网段，唯一例外是「自己的服务器」里登记的那一台；对话口头说明与密钥都不放行。

---

## 还原与卸载

- 每个被改的宿主文件在应用前备份为 `*.dshpurge.bak`；「还原 / `/pojia revert`」用备份覆盖回去。
- `prompt-inject.md` 是用户文件，还原时保留。
- 「卸载」= 先还原补丁 → 移除注入与规则 → 删除插件文件；完成后重启桌面端。

## 工作原理（简）

应用时：备份宿主原件 → 按补丁表替换 `@deepseek-ai` 包内文件 → 注入 shim → 写入提示词覆盖。每轮对话再把提示词挂到系统提示头部。改动只发生在本机你自己的安装里，版本升级后原文对不上会显示跳过，不会乱改。

运行时数据位置：`$DSH_HOME\prompt-inject.md`、`$DSH_HOME\rules\`、`$DSH_HOME\skills\`、`$DSH_HOME\net-scope-allow.txt`、`$DSH_HOME\redteam\`、`$DSH_HOME\dsh-purge\`（状态）。

## 升级

- **插件内一键升级**：会话标题旁 **dsh-pojia** → **清洗** → **版本与更新** → **检测更新** → 有新版就点升级。数据源是本仓库 `https://github.com/suyuhao1206/dsh-pojia` 的 `master`，覆盖 `lib`、`bin`、`docs`、`presets`、`skills` 与根文件后自动重打补丁并重启。
- **手动升级**：解压新包覆盖插件目录 → 重跑 `install.cmd`（或双击）→ 完全退出重开。

> 1.0.2 之前的版本 `REPO` 是占位符 `local/dsh-pojia`，检测更新永远失败；用这份新包覆盖一次之后才能一键升级。

## 使用范围

仅限在自有或已获书面授权的本机环境、离线靶标与合规演练中使用；禁止任何未授权渗透与违法用途。进入演练台前需完成声明授权。
