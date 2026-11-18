#Requires -Version 5.1
<#
.SYNOPSIS
  安装 / 卸载 dsh-pojia 到 DeepSeek Harness 桌面端（不依赖 PATH 里的 dsh，也不依赖 node/pnpm）。

.DESCRIPTION
  多数 Windows 桌面用户没把 dsh 加进 PATH，README 里那句
      dsh plugin --profile desktop add .
  直接跑不起来。本脚本做的是等价的事：
    1) 把插件目录同步到 %USERPROFILE%\.dsh\plugins\dsh-pojia
    2) 在 profile 的 node_modules 下建 junction 指向它
    3) 在 profile 的 package.json 写 dependencies(link:) 与 dsh.profile.bundles
  只动 .dsh 目录，绝不改宿主安装文件；每次改 package.json 前都备份。
  若本机能定位到宿主自带的 node + dsh CLI，会先尝试官方 `plugin add`，失败再退回手工接线。

.PARAMETER Source
  插件目录（含 package.json）。默认取脚本上一级，其次当前目录。

.PARAMETER DshHome
  .dsh 目录。默认读 $env:DSH_HOME，其次 %USERPROFILE%\.dsh。

.PARAMETER ProfileName
  profile 名，桌面端默认 desktop。

.PARAMETER Mode
  auto（默认）先试官方 CLI 再退回接线；link 只接线；cli 只走官方 CLI。

.PARAMETER Uninstall
  从 profile 摘掉插件并删除 junction（插件目录保留，除非同时 -Purge）。

.PARAMETER Purge
  卸载时连 %DSH_HOME%\plugins\dsh-pojia 一起删。

.PARAMETER DryRun
  只打印将要做什么，不落盘。

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-desktop.ps1

.EXAMPLE
  .\scripts\install-desktop.ps1 -Source "D:\code\dsh-pojia" -Mode link -DryRun
#>
[CmdletBinding()]
param(
  [string]$Source = "",
  [string]$DshHome = "",
  [string]$ProfileName = "desktop",
  [ValidateSet("auto", "link", "cli")]
  [string]$Mode = "auto",
  [switch]$Uninstall,
  [switch]$Purge,
  [switch]$DryRun,
  [switch]$NoNode
)

$ErrorActionPreference = "Stop"
$PluginName = "dsh-pojia"

function Write-Step($text) { Write-Host ""; Write-Host "== $text" -ForegroundColor White }
function Write-Ok($text) { Write-Host "   [ok]   $text" -ForegroundColor Green }
function Write-Skip($text) { Write-Host "   [warn] $text" -ForegroundColor Yellow }
function Write-Bad($text) { Write-Host "   [fail] $text" -ForegroundColor Red }
function Write-Note($text) { Write-Host "   [info] $text" -ForegroundColor Gray }

function Resolve-FullPath([string]$path) {
  if (-not $path) { return "" }
  try { return [System.IO.Path]::GetFullPath($path) } catch { return $path }
}

function Test-IsLink([string]$path) {
  try {
    $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
    return [bool]$item.LinkType
  } catch { return $false }
}

function Remove-LinkPath([string]$path) {
  # junction/symlink 只删链接本身：PS5.1 的 Remove-Item -Recurse 会穿透到目标里删文件。
  if (-not (Test-Path -LiteralPath $path)) { return }
  if (Test-IsLink $path) {
    & cmd.exe /c rmdir "$path" 2>&1 | Out-Null
    return
  }
  Remove-Item -LiteralPath $path -Recurse -Force
}

function Find-DshHome {
  if ($DshHome) {
    $full = Resolve-FullPath $DshHome
    if (-not (Test-Path $full)) { throw "指定的 -DshHome 不存在：$full" }
    return $full
  }
  if ($env:DSH_HOME -and (Test-Path $env:DSH_HOME)) { return (Resolve-FullPath $env:DSH_HOME) }
  $cands = @()
  if ($env:USERPROFILE) { $cands += (Join-Path $env:USERPROFILE ".dsh") }
  if ($env:LOCALAPPDATA) { $cands += (Join-Path $env:LOCALAPPDATA ".dsh") }
  foreach ($c in $cands) {
    if (Test-Path (Join-Path $c "profiles")) { return (Resolve-FullPath $c) }
  }
  return ""
}

function Find-DshAppRoot {
  $cands = @()
  if ($env:DSH_APP_ROOT) { $cands += $env:DSH_APP_ROOT }
  $cands += @("D:\app install\DeepSeek Harness")
  if ($env:LOCALAPPDATA) { $cands += (Join-Path $env:LOCALAPPDATA "Programs\DeepSeek Harness") }
  if ($env:ProgramFiles) { $cands += (Join-Path $env:ProgramFiles "DeepSeek Harness") }
  if (${env:ProgramFiles(x86)}) { $cands += (Join-Path ${env:ProgramFiles(x86)} "DeepSeek Harness") }
  foreach ($c in $cands) {
    if ($c -and (Test-Path (Join-Path $c "DeepSeek Harness.exe"))) { return (Resolve-FullPath $c) }
  }
  try {
    $proc = Get-Process -Name "DeepSeek Harness" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc -and $proc.Path) { return (Split-Path $proc.Path -Parent) }
  } catch { }
  return ""
}

function Find-NodeExe([string]$appRoot) {
  if ($appRoot) {
    $p = Join-Path $appRoot "resources\runtime\primary-runtime\dependencies\node\bin\node.exe"
    if (Test-Path $p) { return $p }
  }
  $cmd = Get-Command node -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return ""
}

function Find-DshCliEntry([string]$appRoot) {
  if (-not $appRoot) { return "" }
  $p = Join-Path $appRoot "resources\app\dsh\node_modules\@deepseek-ai\dsh\lib\bin.js"
  if (Test-Path $p) { return $p }
  return ""
}

function Copy-PluginTree([string]$from, [string]$to) {
  $skipDirs = @(".git", "node_modules", ".upstream", ".github", "dist")
  $fromFull = (Resolve-FullPath $from).TrimEnd("\")
  $toFull = (Resolve-FullPath $to).TrimEnd("\")
  if ($fromFull -eq $toFull) { Write-Note "源目录就是安装目录，跳过复制"; return }
  if (-not (Test-Path $toFull)) { New-Item -ItemType Directory -Path $toFull -Force | Out-Null }

  $copied = 0
  foreach ($item in (Get-ChildItem -LiteralPath $fromFull -Force)) {
    if ($item.PSIsContainer -and ($skipDirs -contains $item.Name)) { continue }
    if (-not $item.PSIsContainer) {
      if ($item.Name -match '\.(zip|7z|bak|tgz)$') { continue }
      if ($item.Name -match '\.prev\d*$') { continue }
    }
    $dest = Join-Path $toFull $item.Name
    if ($item.PSIsContainer) {
      if (Test-Path -LiteralPath $dest) { Remove-LinkPath $dest }
      Copy-Item -LiteralPath $item.FullName -Destination $dest -Recurse -Force
    } else {
      Copy-Item -LiteralPath $item.FullName -Destination $dest -Force
    }
    $copied += 1
  }
  Write-Ok "已同步 $copied 个顶层条目 → $toFull"
}

function Invoke-JsonEdit([string]$nodeExe, [string]$pkgPath, [string]$action, [string]$linkSpec) {
  $editor = @'
const fs = require("fs");
const [,, file, name, spec, act] = process.argv;
const pkg = JSON.parse(fs.readFileSync(file, "utf8"));
if (act === "add") {
  pkg.dependencies = pkg.dependencies && typeof pkg.dependencies === "object" ? pkg.dependencies : {};
  pkg.dsh = pkg.dsh && typeof pkg.dsh === "object" ? pkg.dsh : {};
  pkg.dsh.profile = pkg.dsh.profile && typeof pkg.dsh.profile === "object" ? pkg.dsh.profile : {};
  const bundles = Array.isArray(pkg.dsh.profile.bundles) ? pkg.dsh.profile.bundles : (pkg.dsh.profile.bundles = []);
  pkg.dependencies[name] = spec;
  if (!bundles.includes(name)) bundles.push(name);
} else {
  if (pkg.dependencies && typeof pkg.dependencies === "object") delete pkg.dependencies[name];
  const profile = pkg.dsh && pkg.dsh.profile;
  if (profile && Array.isArray(profile.bundles)) profile.bundles = profile.bundles.filter((x) => x !== name);
}
fs.writeFileSync(file, JSON.stringify(pkg, null, 2) + "\n", "utf8");
JSON.parse(fs.readFileSync(file, "utf8"));
console.log("json-ok");
'@
  $tmp = Join-Path $env:TEMP ("dshpojia-json-" + [System.Guid]::NewGuid().ToString("N") + ".cjs")
  [System.IO.File]::WriteAllText($tmp, $editor, (New-Object System.Text.UTF8Encoding($false)))
  try {
    $out = & $nodeExe $tmp $pkgPath $PluginName $linkSpec $action 2>&1
    if ($LASTEXITCODE -ne 0) { throw ("package.json 写入失败：" + ($out -join " ")) }
  } finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  }
}

function Invoke-JsonEditFallback([string]$pkgPath, [string]$action, [string]$linkSpec) {
  $raw = [System.IO.File]::ReadAllText($pkgPath, [System.Text.Encoding]::UTF8)
  $esc = [regex]::Escape($PluginName)
  if ($action -eq "add") {
    if ($raw -match ('"' + $esc + '"\s*:\s*"link:[^"]*"')) {
      $raw = [regex]::Replace($raw, ('"' + $esc + '"\s*:\s*"link:[^"]*"'), ('"' + $PluginName + '": "' + $linkSpec + '"'))
    } else {
      $raw = [regex]::Replace($raw, '("dependencies"\s*:\s*\{)', ('$1' + "`n    `"$PluginName`": `"$linkSpec`","), 1)
    }
    $bundleRe = [regex]'("bundles"\s*:\s*\[)([\s\S]*?)(\s*\])'
    $name = $PluginName
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
      param($m)
      $inner = $m.Groups[2].Value
      if ($inner -match [regex]::Escape($name)) { return $m.Value }
      $trimmed = $inner.TrimEnd()
      $sep = ""
      if ($trimmed.Trim().Length -gt 0) { $sep = "," }
      $nl = "`n        `"" + $name + "`""
      return $m.Groups[1].Value + $trimmed + $sep + $nl + $m.Groups[3].Value
    }
    $raw = $bundleRe.Replace($raw, $evaluator, 1)
  } else {
    $raw = [regex]::Replace($raw, '(\s*)"' + $esc + '"\s*:\s*"link:[^"]*",?', '')
    $raw = [regex]::Replace($raw, ',\s*"' + $esc + '"', '')
  }
  $null = $raw | ConvertFrom-Json
  [System.IO.File]::WriteAllText($pkgPath, $raw, (New-Object System.Text.UTF8Encoding($false)))
  Write-Note "package.json 用文本方式改写（没有 node），已重新解析校验"
}

function Invoke-OfficialCli([string]$nodeExe, [string]$cliEntry, [string]$pluginDir, [string]$homeDir) {
  if (-not $nodeExe -or -not $cliEntry) { return $false }
  $old = $env:DSH_HOME
  $env:DSH_HOME = $homeDir
  try {
    Write-Note "尝试官方 CLI：node bin.js plugin --profile $ProfileName add `"$pluginDir`""
    $cliArgs = @($cliEntry, "plugin", "--profile", $ProfileName, "add", $pluginDir)
    $out = & $nodeExe @cliArgs 2>&1
    $code = $LASTEXITCODE
    $text = ($out | Out-String).Trim()
    if ($text) { Write-Note $text }
    return ($code -eq 0)
  } catch {
    Write-Note ("官方 CLI 抛错：" + $_.Exception.Message)
    return $false
  } finally {
    if ($null -eq $old) { Remove-Item Env:\DSH_HOME -ErrorAction SilentlyContinue } else { $env:DSH_HOME = $old }
  }
}

# ------------------------------------------------------------------ main

Write-Host "dsh-pojia 安装器 / installer" -ForegroundColor Cyan
Write-Host "  面向 Windows 桌面端；Linux/macOS 用 dsh plugin add 即可。" -ForegroundColor DarkGray

Write-Step "1/5 环境探测"
$dshHomeDir = Find-DshHome
if (-not $dshHomeDir) {
  Write-Bad "找不到 .dsh 目录。先用桌面端跑一次，或用 -DshHome 指定。"
  exit 2
}
Write-Ok "DSH_HOME  = $dshHomeDir"

$profileDir = Join-Path $dshHomeDir ("profiles\" + $ProfileName)
if (-not (Test-Path $profileDir)) {
  Write-Bad "profile 不存在：$profileDir"
  Write-Note "先启动一次桌面端让它生成 desktop profile，再跑本脚本。"
  exit 2
}
Write-Ok "profile   = $profileDir"

$appRoot = Find-DshAppRoot
$nodeExe = Find-NodeExe $appRoot
$cliEntry = Find-DshCliEntry $appRoot
if ($appRoot) { Write-Ok "dsh 安装  = $appRoot" } else { Write-Skip "没找到 DeepSeek Harness 安装目录（只接线，不影响）" }
if ($nodeExe) { Write-Ok "node      = $nodeExe" } else { Write-Skip "没找到 node，package.json 改用文本改写" }
if ($cliEntry) { Write-Ok "dsh CLI   = $cliEntry" } else { Write-Skip "没找到 @deepseek-ai/dsh/lib/bin.js，官方 CLI 模式不可用" }

$pkgPath = Join-Path $profileDir "package.json"
$nmDir = Join-Path $profileDir "node_modules"
$linkPath = Join-Path $nmDir $PluginName
$installDir = Join-Path $dshHomeDir ("plugins\" + $PluginName)

if ($Uninstall) {
  Write-Step "卸载 profile 接线"
  if (-not (Test-Path $pkgPath)) { Write-Bad "没有 package.json：$pkgPath"; exit 2 }
  $bak = "$pkgPath.bak-dshpojia-" + (Get-Date -Format "yyyyMMdd-HHmmss")
  if ($DryRun) {
    Write-Note "[dry-run] 会备份并移除 dependencies/bundles 里的 $PluginName"
  } elseif ($nodeExe -and -not $NoNode) {
    Copy-Item $pkgPath $bak -Force
    Invoke-JsonEdit $nodeExe $pkgPath "remove" ""
    Write-Ok "已从 profile 摘掉 $PluginName（备份 $bak）"
  } else {
    Copy-Item $pkgPath $bak -Force
    Invoke-JsonEditFallback $pkgPath "remove" ""
    Write-Ok "已从 profile 摘掉 $PluginName（备份 $bak）"
  }
  if (Test-Path -LiteralPath $linkPath) {
    if ($DryRun) { Write-Note "[dry-run] 会删除 $linkPath" }
    else { Remove-LinkPath $linkPath; Write-Ok "已删除 $linkPath" }
  } else {
    Write-Note "node_modules 里本来没有 $PluginName"
  }
  if ($Purge -and (Test-Path $installDir)) {
    if ($DryRun) { Write-Note "[dry-run] 会删除 $installDir" }
    else { Remove-Item $installDir -Recurse -Force; Write-Ok "已删除 $installDir" }
  }
  Write-Host ""
  Write-Host "卸载完成。完全退出并重开桌面端生效。" -ForegroundColor Cyan
  exit 0
}

Write-Step "2/5 准备插件目录"
$srcDir = ""
if ($Source) {
  $srcDir = Resolve-FullPath $Source
} else {
  $here = Split-Path -Parent $PSCommandPath
  $cands = @((Split-Path -Parent $here), (Resolve-FullPath "."), $installDir)
  foreach ($c in $cands) {
    if ($c -and (Test-Path (Join-Path $c "package.json"))) { $srcDir = (Resolve-FullPath $c); break }
  }
}
if (-not $srcDir -or -not (Test-Path (Join-Path $srcDir "package.json"))) {
  Write-Bad "找不到插件目录（要有 package.json）。用 -Source 指到解包后的 dsh-pojia 目录。"
  exit 2
}
$srcPkg = Get-Content (Join-Path $srcDir "package.json") -Raw | ConvertFrom-Json
Write-Ok "源目录    = $srcDir"
Write-Ok ("插件版本  = " + $srcPkg.version + "  (" + $srcPkg.name + ")")

if ($DryRun) {
  Write-Note "[dry-run] 会同步 $srcDir → $installDir"
  $targetDir = if (Test-Path $installDir) { $installDir } else { $srcDir }
} else {
  Copy-PluginTree $srcDir $installDir
  $targetDir = $installDir
}
Write-Ok "插件目录  = $targetDir"

Write-Step "3/5 接线到 profile"
$linkSpec = "link:" + ($targetDir -replace "\\", "/")
$needManual = $true

if ($Mode -eq "auto" -or $Mode -eq "cli") {
  if ($DryRun) {
    Write-Note "[dry-run] 会先尝试官方 CLI"
  } else {
    $cliOk = Invoke-OfficialCli $nodeExe $cliEntry $targetDir $dshHomeDir
    if ($cliOk) { Write-Ok "官方 CLI 安装完成"; $needManual = $false }
    elseif ($Mode -eq "cli") { Write-Bad "官方 CLI 失败，且指定了 -Mode cli"; exit 3 }
    else { Write-Skip "官方 CLI 没成功，改用手工接线" }
  }
}

if ($needManual) {
  if (-not (Test-Path $nmDir)) {
    if ($DryRun) { Write-Note "[dry-run] 会创建 $nmDir" } else { New-Item -ItemType Directory -Path $nmDir -Force | Out-Null }
  }
  if (Test-Path -LiteralPath $linkPath) {
    Write-Note ("已存在 $linkPath（LinkType=" + (Get-Item -LiteralPath $linkPath -Force).LinkType + "），先移除")
    if (-not $DryRun) { Remove-LinkPath $linkPath }
  }
  if ($DryRun) {
    Write-Note "[dry-run] 会建 junction $linkPath → $targetDir"
  } else {
    $null = New-Item -ItemType Junction -Path $linkPath -Target $targetDir
    Write-Ok "junction 已建：$linkPath → $targetDir"
  }

  $bak = "$pkgPath.bak-dshpojia-" + (Get-Date -Format "yyyyMMdd-HHmmss")
  if ($DryRun) {
    Write-Note "[dry-run] 会备份 package.json → $bak，并写入 dependencies.$PluginName = $linkSpec 与 bundles"
  } else {
    Copy-Item $pkgPath $bak -Force
    Write-Note "备份 → $bak"
    if ($nodeExe -and -not $NoNode) { Invoke-JsonEdit $nodeExe $pkgPath "add" $linkSpec }
    else { Invoke-JsonEditFallback $pkgPath "add" $linkSpec }
    $check = Get-Content $pkgPath -Raw | ConvertFrom-Json
    if (-not ($check.PSObject.Properties.Name -contains "dsh")) {
      Write-Bad "package.json 写入后结构异常，用备份恢复：$bak"
      exit 4
    }
    Write-Ok "package.json 已写入 dependencies.$PluginName = $linkSpec"
  }
}

Write-Step "4/5 校验"
if ($DryRun) {
  Write-Note "[dry-run] 跳过实际校验"
} else {
  $resolved = Join-Path $linkPath "package.json"
  if (Test-Path $resolved) { Write-Ok "profile 能解析到插件：$resolved" } else { Write-Bad "profile 解析不到插件，检查 $linkPath" }
  $pkgNow = Get-Content $pkgPath -Raw | ConvertFrom-Json
  $bundles = @()
  try { $bundles = @($pkgNow.dsh.profile.bundles) } catch { }
  if ($bundles -contains $PluginName) { Write-Ok "bundles 已包含 $PluginName" } else { Write-Bad "bundles 里没有 $PluginName" }
}

Write-Step "5/5 下一步"
Write-Host "   1) 完全退出桌面端（托盘也要退），再重新打开" -ForegroundColor White
Write-Host "   2) 会话标题旁点 dsh-pojia → 清洗 → 应用" -ForegroundColor White
Write-Host "   3) 应用后会自动重启一次，重启后新开一轮对话" -ForegroundColor White
Write-Host ""
Write-Host "装机完成。" -ForegroundColor Green
