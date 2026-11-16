/**
 * anchor-check：官方发版后的锚点健康自检。
 *
 * 用法：
 *   node scripts/anchor-check.mjs <dsh版本号>            # 安装该版本依赖树并体检
 *   node scripts/anchor-check.mjs <dsh版本号> --verify   # 额外做替换模拟 + node --check 回归
 *   node scripts/anchor-check.mjs --local <aiBase路径>    # 直接体检本机已有目录
 *
 * 输出：功能健康度（features）、逐补丁状态、与上一棵基线树的锚点增删 diff。
 * 依赖：node >= 18，可访问 npm registry（安装依赖树时）。
 */
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const upstream = path.join(root, ".upstream");

async function main() {
  const argv = process.argv.slice(2);
  const localIdx = argv.indexOf("--local");
  let aiBase = "";
  let tag = "";
  if (localIdx >= 0) {
    aiBase = path.resolve(argv[localIdx + 1] || "");
    tag = "local:" + aiBase;
  } else {
    const version = argv.find((a) => !a.startsWith("--"));
    if (!version) {
      console.error("用法: node scripts/anchor-check.mjs <dsh版本号> [--verify]  或  --local <aiBase>");
      process.exit(1);
    }
    tag = version;
    const dir = path.join(upstream, "check-" + version.replace(/[^\w.-]/g, "_"));
    if (!existsSync(path.join(dir, "node_modules", "@deepseek-ai", "dsh", "package.json"))) {
      mkdirSync(dir, { recursive: true });
      const pkg = path.join(dir, "package.json");
      if (!existsSync(pkg)) writeFileSync(pkg, JSON.stringify({ name: "anchor-check", private: true, version: "0.0.0" }, null, 2));
      console.log("[install] @deepseek-ai/dsh@" + version + " -> " + dir);
      execFileSync(process.platform === "win32" ? "npm.cmd" : "npm",
        ["install", "--no-audit", "--no-fund", "--loglevel=error", "@deepseek-ai/dsh@" + version],
        { cwd: dir, stdio: "inherit" });
    }
    aiBase = path.join(dir, "node_modules", "@deepseek-ai");
  }

  process.env.DSH_SURFACE = process.env.DSH_SURFACE || "desktop";
  const core = await import(pathToFileURL(path.join(root, "lib", "core.js")).href);
  const all = core.ALL_PATCHES;
  console.log(`\n[patch status] aiBase=${aiBase}`);
  const status = await core.patchStatus(aiBase);
  const bad = [];
  for (const p of all) {
    const st = status[p.id] ?? "?";
    if (["pending", "unmatched", "pattern_not_found", "missing_file"].includes(st)) bad.push({ id: p.id, name: p.name, st });
    console.log(`  ${String(p.id).padStart(3)} ${String(st).padEnd(13)} ${p.name}`);
  }
  console.log(`\n[features]`);
  const fh = core.featureHealth(status, all);
  for (const f of fh.features) {
    console.log(`  ${f.status === "warn" ? "✗" : "✓"} ${f.title}${f.warn.length ? "  <- " + f.warn.map((w) => "#" + w.id).join(",") : ""}`);
  }
  console.log(`\nwarn features: ${fh.warnCount}/${fh.features.length}`);
  console.log(`patches needing attention: ${bad.length ? bad.map((b) => "#" + b.id + " " + b.name + " (" + b.st + ")").join("; ") : "none"}`);

  if (argv.includes("--verify")) {
    const { applyReplacementsToText, targetFiles, filePatchSettled } = core;
    const { readFileSync: rf, writeFileSync: wf, mkdirSync: mk } = await import("node:fs");
    const outRoot = path.join(upstream, "check-syntax");
    const files = targetFiles(aiBase);
    const pathsOf = (files, key) => {
      const v = files[key];
      return !v ? [] : Array.isArray(v) ? v.filter(Boolean) : [v];
    };
    let js = 0;
    let fail = 0;
    for (const p of all) {
      if (!core.patchAppliesHere(p)) continue;
      for (const key of (Array.isArray(p.file) ? p.file : [p.file])) {
        for (const fp of pathsOf(files, key)) {
          let text;
          try { text = rf(fp, "utf8"); } catch { continue; }
          const out = applyReplacementsToText(text, p, fp);
          if (!out.changed && !filePatchSettled(text, p, fp)) continue;
          if (!out.changed) continue;
          const dst = path.join(outRoot, path.relative(aiBase, fp));
          mk(path.dirname(dst), { recursive: true });
          wf(dst, out.text);
          if (dst.endsWith(".js")) {
            js += 1;
            try { execFileSync(process.execPath, ["--check", dst], { stdio: "pipe" }); } catch (e) {
              fail += 1;
              console.log("SYNTAX FAIL:", dst, String(e.stderr || e.message).slice(0, 300));
            }
          }
        }
      }
    }
    console.log(`[verify] patched ${js} js files, syntax failures: ${fail}`);
    rmSync(outRoot, { recursive: true, force: true });
  }
}

main().catch((e) => { console.error(e); process.exit(1); });
