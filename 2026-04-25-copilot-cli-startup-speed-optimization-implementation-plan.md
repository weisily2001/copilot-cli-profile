# Copilot CLI 启动速度优化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 Copilot CLI 增加轻量启动观测、收敛 hook 的重复项目解析，并降低启动链路中的重复探测与长时间阻塞风险。

**Architecture:** 先新增一个独立的启动观测脚本，把冷启动拆成可测的阶段并输出轻量结构化结果；再把 `session-start.ps1` 和 `session-end.ps1` 共享的项目解析逻辑提取到公共 helper，并引入“最近项目快速命中”机制减少重复扫描；最后补一套登录状态诊断脚本，并在确认 hook 稳定变快后下调 hook 超时，减少极端情况下的启动卡顿。

**Tech Stack:** PowerShell 5+/7、JSON / JSONL、Copilot CLI 全局配置文件、会话 hooks

---

## File Structure

- Create: `C:\Users\HP\.copilot\diagnostics\measure-startup.ps1` — 启动观测入口，记录总耗时与阶段耗时
- Create: `C:\Users\HP\.copilot\diagnostics\measure-startup-smoke.ps1` — 启动观测脚本的本地烟雾测试
- Create: `C:\Users\HP\.copilot\diagnostics\inspect-login-state.ps1` — 检查本地登录缓存与登录摩擦相关状态
- Create: `C:\Users\HP\.copilot\hooks\ecc-memory\shared.ps1` — hook 共享 helper：项目解析、最近项目快速命中、轻量指标写入
- Modify: `C:\Users\HP\.copilot\hooks\ecc-memory\session-start.ps1` — 改为调用共享 helper，记录启动阶段指标
- Modify: `C:\Users\HP\.copilot\hooks\ecc-memory\session-end.ps1` — 改为调用共享 helper，写回最近项目元数据并记录阶段指标
- Modify: `C:\Users\HP\.copilot\settings.json` — 在 hook 路径稳定变快后下调 timeout，减少长卡顿风险
- Create: `C:\Users\HP\.copilot\startup-observability.md` — 说明观测字段、日志位置、保留策略、诊断方式

### Task 1: 新增启动观测入口与烟雾测试

**Files:**
- Create: `C:\Users\HP\.copilot\diagnostics\measure-startup.ps1`
- Create: `C:\Users\HP\.copilot\diagnostics\measure-startup-smoke.ps1`
- Create: `C:\Users\HP\.copilot\startup-observability.md`

- [ ] **Step 1: 先写会失败的烟雾测试**

Create:

```powershell
param()

$ErrorActionPreference = 'Stop'
$scriptPath = 'C:\Users\HP\.copilot\diagnostics\measure-startup.ps1'

if (-not (Test-Path $scriptPath)) {
  throw "Missing script: $scriptPath"
}

$result = & $scriptPath -Runs 1 | ConvertFrom-Json

if ($null -eq $result.totalMs) {
  throw 'Missing totalMs'
}

if ($null -eq $result.phases.hookStartMs) {
  throw 'Missing phases.hookStartMs'
}

if ($null -eq $result.loginState.hasCachedLogin) {
  throw 'Missing loginState.hasCachedLogin'
}

Write-Host 'measure-startup smoke PASS'
```

- [ ] **Step 2: 运行烟雾测试并确认失败**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\HP\.copilot\diagnostics\measure-startup-smoke.ps1"
```

Expected:

```text
Missing script: C:\Users\HP\.copilot\diagnostics\measure-startup.ps1
```

- [ ] **Step 3: 写最小启动观测脚本**

Create:

```powershell
param(
  [int]$Runs = 1
)

$ErrorActionPreference = 'Stop'
$copilotHome = Join-Path $HOME '.copilot'
$metricsPath = Join-Path $copilotHome 'startup-metrics.jsonl'
$configPath = Join-Path $copilotHome 'config.json'
$hookStart = Join-Path $copilotHome 'hooks\ecc-memory\session-start.ps1'
$hookEnd = Join-Path $copilotHome 'hooks\ecc-memory\session-end.ps1'

function Get-LoginState {
  param([string]$Path)

  if (-not (Test-Path $Path)) {
    return @{
      hasCachedLogin = $false
      lastLogin = $null
    }
  }

  $config = Get-Content -Path $Path -Raw | ConvertFrom-Json
  return @{
    hasCachedLogin = ($null -ne $config.lastLoggedInUser)
    lastLogin = if ($null -ne $config.lastLoggedInUser) { [string]$config.lastLoggedInUser.login } else { $null }
  }
}

function Measure-Phase {
  param(
    [string]$Name,
    [scriptblock]$Action
  )

  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  & $Action | Out-Null
  $sw.Stop()
  return @{
    name = $Name
    ms = $sw.ElapsedMilliseconds
  }
}

$runs = @()
for ($i = 0; $i -lt $Runs; $i++) {
  $total = [System.Diagnostics.Stopwatch]::StartNew()

  $loginState = Get-LoginState -Path $configPath
  $hookStartMetric = Measure-Phase -Name 'hookStartMs' -Action { & $hookStart *> $null }
  $hookEndMetric = Measure-Phase -Name 'hookEndMs' -Action { & $hookEnd *> $null }

  $total.Stop()

  $run = [ordered]@{
    timestamp = Get-Date -Format o
    totalMs = $total.ElapsedMilliseconds
    phases = @{
      hookStartMs = $hookStartMetric.ms
      hookEndMs = $hookEndMetric.ms
    }
    loginState = $loginState
  }

  $runs += $run

  ($run | ConvertTo-Json -Compress) | Add-Content -Path $metricsPath -Encoding UTF8
}

$runs[-1] | ConvertTo-Json -Depth 5
```

- [ ] **Step 4: 写观测说明文档**

Create:

```md
# 启动观测说明

## 观测文件

- 指标日志：`C:\Users\HP\.copilot\startup-metrics.jsonl`
- 诊断脚本：`C:\Users\HP\.copilot\diagnostics\measure-startup.ps1`

## 当前字段

- `totalMs`
- `phases.hookStartMs`
- `phases.hookEndMs`
- `loginState.hasCachedLogin`
- `loginState.lastLogin`

## 使用方式

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\HP\.copilot\diagnostics\measure-startup.ps1" -Runs 3
```

## 保留策略

- 默认保留最近少量观测
- 日志只用于启动诊断，不进入项目记忆目录
```

- [ ] **Step 5: 重新运行烟雾测试并确认通过**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\HP\.copilot\diagnostics\measure-startup-smoke.ps1"
```

Expected:

```text
measure-startup smoke PASS
```

### Task 2: 提取 hook 共享 helper，并加入最近项目快速命中

**Files:**
- Create: `C:\Users\HP\.copilot\hooks\ecc-memory\shared.ps1`
- Modify: `C:\Users\HP\.copilot\hooks\ecc-memory\session-start.ps1`
- Modify: `C:\Users\HP\.copilot\hooks\ecc-memory\session-end.ps1`
- Create: `C:\Users\HP\.copilot\diagnostics\hook-resolution-smoke.ps1`

- [ ] **Step 1: 先写会失败的解析烟雾测试**

Create:

```powershell
param()

$ErrorActionPreference = 'Stop'
$shared = 'C:\Users\HP\.copilot\hooks\ecc-memory\shared.ps1'
if (-not (Test-Path $shared)) {
  throw "Missing shared helper: $shared"
}

. $shared

$projectsRoot = Join-Path $HOME '.copilot\memory\projects'
$context = Resolve-ProjectContextFast -Path 'C:\Users\HP\Desktop\copilot-ecc-bootstrap-test' -ProjectsRoot $projectsRoot

if ($null -eq $context) {
  throw 'Resolve-ProjectContextFast returned null'
}

if ([string]::IsNullOrWhiteSpace($context.ProjectKey)) {
  throw 'Missing ProjectKey'
}

if ([string]::IsNullOrWhiteSpace($context.ProjectRoot)) {
  throw 'Missing ProjectRoot'
}

Write-Host 'hook-resolution smoke PASS'
```

- [ ] **Step 2: 运行烟雾测试并确认失败**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\HP\.copilot\diagnostics\hook-resolution-smoke.ps1"
```

Expected:

```text
Missing shared helper: C:\Users\HP\.copilot\hooks\ecc-memory\shared.ps1
```

- [ ] **Step 3: 写共享 helper**

Create:

```powershell
$ErrorActionPreference = 'Stop'
$CopilotHome = Join-Path $HOME '.copilot'
$ProjectsRootDefault = Join-Path $CopilotHome 'memory\projects'
$ProjectContextCachePath = Join-Path $CopilotHome 'project-context-cache.json'

function Test-IsSameOrChildPath {
  param(
    [string]$Path,
    [string]$CandidateRoot
  )

  if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($CandidateRoot)) {
    return $false
  }

  $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
  $fullRoot = [System.IO.Path]::GetFullPath($CandidateRoot).TrimEnd('\')

  if ($fullPath.Equals($fullRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $true
  }

  return $fullPath.StartsWith("$fullRoot\", [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-ProjectContextCache {
  if (-not (Test-Path $ProjectContextCachePath)) {
    return $null
  }

  try {
    return Get-Content -Path $ProjectContextCachePath -Raw | ConvertFrom-Json
  }
  catch {
    return $null
  }
}

function Get-RecordedProjectContext {
  param([string]$ProjectDir)

  $projectJsonPath = Join-Path $ProjectDir 'project.json'
  if (-not (Test-Path $projectJsonPath)) {
    return $null
  }

  try {
    $projectMeta = Get-Content -Path $projectJsonPath -Raw | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace([string]$projectMeta.projectRoot)) {
      return $null
    }

    return [pscustomobject]@{
      ProjectKey = if ([string]::IsNullOrWhiteSpace([string]$projectMeta.projectKey)) { (Split-Path $ProjectDir -Leaf).ToLowerInvariant() } else { ([string]$projectMeta.projectKey).Trim().ToLowerInvariant() }
      ProjectRoot = ([string]$projectMeta.projectRoot).Trim()
    }
  }
  catch {
    return $null
  }
}

function Resolve-ProjectContextFast {
  param(
    [string]$Path,
    [string]$ProjectsRoot = $ProjectsRootDefault
  )

  $last = Get-ProjectContextCache
  if ($last -and (Test-IsSameOrChildPath -Path $Path -CandidateRoot ([string]$last.projectRoot))) {
    return [pscustomobject]@{
      ProjectKey = ([string]$last.projectKey).Trim().ToLowerInvariant()
      ProjectRoot = ([string]$last.projectRoot).Trim()
    }
  }

  foreach ($projectDir in Get-ChildItem -Path $ProjectsRoot -Directory) {
    $context = Get-RecordedProjectContext -ProjectDir $projectDir.FullName
    if ($null -eq $context) {
      continue
    }

    if (Test-IsSameOrChildPath -Path $Path -CandidateRoot $context.ProjectRoot) {
      return $context
    }
  }

  return $null
}

function Write-LastSessionMetadata {
  param(
    [string]$ProjectKey,
    [string]$ProjectRoot,
    [string]$EventName
  )

  $targetPath = Join-Path (Join-Path $ProjectsRootDefault $ProjectKey) 'last-session.json'
  $payload = @{
    event = $EventName
    projectRoot = $ProjectRoot
    projectKey = $ProjectKey
    timestamp = Get-Date -Format o
  } | ConvertTo-Json -Compress

  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($targetPath, $payload, $utf8NoBom)
  [System.IO.File]::WriteAllText($ProjectContextCachePath, $payload, $utf8NoBom)
}
```

- [ ] **Step 4: 让 session-start.ps1 使用共享 helper**

Replace body with:

```powershell
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $HOME '.copilot\hooks\ecc-memory\shared.ps1')
$currentPath = (Get-Location).Path

try {
  $project = Resolve-ProjectContextFast -Path $currentPath
  if ($null -eq $project) {
    [Console]::Error.WriteLine("Warning: could not resolve memory project for '$currentPath'.")
  }
  else {
    Write-LastSessionMetadata -ProjectKey $project.ProjectKey -ProjectRoot $project.ProjectRoot -EventName 'sessionStart'
  }
}
catch {
  [Console]::Error.WriteLine("Warning: session-start hook failed: $($_.Exception.Message)")
}
finally {
  Write-Output '{"continue":true}'
}
```

- [ ] **Step 5: 让 session-end.ps1 使用共享 helper**

Replace body with:

```powershell
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $HOME '.copilot\hooks\ecc-memory\shared.ps1')
$currentPath = (Get-Location).Path

try {
  $project = Resolve-ProjectContextFast -Path $currentPath
  if ($null -eq $project) {
    [Console]::Error.WriteLine("Warning: could not resolve memory project for '$currentPath'.")
  }
  else {
    Write-LastSessionMetadata -ProjectKey $project.ProjectKey -ProjectRoot $project.ProjectRoot -EventName 'sessionEnd'
  }
}
catch {
  [Console]::Error.WriteLine("Warning: session-end hook failed: $($_.Exception.Message)")
}
finally {
  Write-Output '{"continue":true}'
}
```

- [ ] **Step 6: 重新运行解析烟雾测试并确认通过**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\HP\.copilot\diagnostics\hook-resolution-smoke.ps1"
```

Expected:

```text
hook-resolution smoke PASS
```

### Task 3: 给 hook 增加轻量指标写入与保留策略

**Files:**
- Modify: `C:\Users\HP\.copilot\diagnostics\measure-startup.ps1`
- Modify: `C:\Users\HP\.copilot\hooks\ecc-memory\shared.ps1`
- Modify: `C:\Users\HP\.copilot\hooks\ecc-memory\session-start.ps1`
- Modify: `C:\Users\HP\.copilot\hooks\ecc-memory\session-end.ps1`

- [ ] **Step 1: 先给观测脚本加会失败的字段断言**

Append to `measure-startup-smoke.ps1`:

```powershell
if ($null -eq $result.phases.resolveProjectMs) {
  throw 'Missing phases.resolveProjectMs'
}

if ($null -eq $result.phases.writeMetadataMs) {
  throw 'Missing phases.writeMetadataMs'
}
```

- [ ] **Step 2: 运行烟雾测试并确认失败**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\HP\.copilot\diagnostics\measure-startup-smoke.ps1"
```

Expected:

```text
Missing phases.resolveProjectMs
```

- [ ] **Step 3: 在 shared.ps1 中增加指标写入 helper**

Append:

```powershell
$StartupMetricsPath = Join-Path $CopilotHome 'startup-metrics.jsonl'

function Write-StartupMetric {
  param(
    [string]$HookName,
    [hashtable]$Phases,
    [string]$ProjectKey
  )

  $record = @{
    timestamp = Get-Date -Format o
    hook = $HookName
    projectKey = $ProjectKey
    phases = $Phases
  } | ConvertTo-Json -Compress

  Add-Content -Path $StartupMetricsPath -Value $record -Encoding UTF8

  $lines = Get-Content -Path $StartupMetricsPath
  if ($lines.Count -gt 20) {
    $lines | Select-Object -Last 20 | Set-Content -Path $StartupMetricsPath -Encoding UTF8
  }
}
```

- [ ] **Step 4: 让 measure-startup.ps1 合并 hook 明细字段**

Insert before final output:

```powershell
$latestHookMetric = Get-Content -Path $metricsPath | Select-Object -Last 1 | ConvertFrom-Json
if ($null -ne $latestHookMetric -and $null -ne $latestHookMetric.phases) {
  $run.phases.resolveProjectMs = $latestHookMetric.phases.resolveProjectMs
  $run.phases.writeMetadataMs = $latestHookMetric.phases.writeMetadataMs
}
```

- [ ] **Step 5: 在 session-start.ps1 中记录阶段耗时**

Replace the `try` block with:

```powershell
try {
  $swResolve = [System.Diagnostics.Stopwatch]::StartNew()
  $project = Resolve-ProjectContextFast -Path $currentPath
  $swResolve.Stop()

  $writeMs = 0
  if ($null -eq $project) {
    [Console]::Error.WriteLine("Warning: could not resolve memory project for '$currentPath'.")
  }
  else {
    $swWrite = [System.Diagnostics.Stopwatch]::StartNew()
    Write-LastSessionMetadata -ProjectKey $project.ProjectKey -ProjectRoot $project.ProjectRoot -EventName 'sessionStart'
    $swWrite.Stop()
    $writeMs = $swWrite.ElapsedMilliseconds
  }

  Write-StartupMetric -HookName 'sessionStart' -ProjectKey $project.ProjectKey -Phases @{
    resolveProjectMs = $swResolve.ElapsedMilliseconds
    writeMetadataMs = $writeMs
  }
}
```

- [ ] **Step 6: 在 session-end.ps1 中记录阶段耗时**

Replace the `try` block with:

```powershell
try {
  $swResolve = [System.Diagnostics.Stopwatch]::StartNew()
  $project = Resolve-ProjectContextFast -Path $currentPath
  $swResolve.Stop()

  $writeMs = 0
  if ($null -eq $project) {
    [Console]::Error.WriteLine("Warning: could not resolve memory project for '$currentPath'.")
  }
  else {
    $swWrite = [System.Diagnostics.Stopwatch]::StartNew()
    Write-LastSessionMetadata -ProjectKey $project.ProjectKey -ProjectRoot $project.ProjectRoot -EventName 'sessionEnd'
    $swWrite.Stop()
    $writeMs = $swWrite.ElapsedMilliseconds
  }

  Write-StartupMetric -HookName 'sessionEnd' -ProjectKey $project.ProjectKey -Phases @{
    resolveProjectMs = $swResolve.ElapsedMilliseconds
    writeMetadataMs = $writeMs
  }
}
```

- [ ] **Step 7: 重新运行启动观测烟雾测试并确认通过**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\HP\.copilot\diagnostics\measure-startup-smoke.ps1"
```

Expected:

```text
measure-startup smoke PASS
```

### Task 4: 增加登录状态诊断并下调 hook 超时

**Files:**
- Create: `C:\Users\HP\.copilot\diagnostics\inspect-login-state.ps1`
- Modify: `C:\Users\HP\.copilot\settings.json`

- [ ] **Step 1: 先写会失败的登录诊断检查**

Run:

```powershell
if (-not (Test-Path "C:\Users\HP\.copilot\diagnostics\inspect-login-state.ps1")) {
  throw 'Missing inspect-login-state.ps1'
}
```

Expected:

```text
Missing inspect-login-state.ps1
```

- [ ] **Step 2: 写登录状态诊断脚本**

Create:

```powershell
param()

$ErrorActionPreference = 'Stop'
$configPath = Join-Path $HOME '.copilot\config.json'

if (-not (Test-Path $configPath)) {
  throw "Missing config.json: $configPath"
}

$config = Get-Content -Path $configPath -Raw | ConvertFrom-Json

[pscustomobject]@{
  hasCachedLogin = ($null -ne $config.lastLoggedInUser)
  lastLoginHost = if ($null -ne $config.lastLoggedInUser) { [string]$config.lastLoggedInUser.host } else { $null }
  lastLoginUser = if ($null -ne $config.lastLoggedInUser) { [string]$config.lastLoggedInUser.login } else { $null }
  trustedFolders = @($config.trustedFolders).Count
} | ConvertTo-Json -Depth 3
```

- [ ] **Step 3: 运行登录状态诊断并确认通过**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\HP\.copilot\diagnostics\inspect-login-state.ps1"
```

Expected:

```text
{
  "hasCachedLogin": true,
  "lastLoginHost": "https://github.com",
  "lastLoginUser": "weisily2001"
}
```

- [ ] **Step 4: 在 settings.json 中下调 hook timeout**

Modify:

```json
"hooks": {
  "sessionStart": [
    {
      "type": "command",
      "powershell": "& \"$HOME\\\\.copilot\\\\hooks\\\\ecc-memory\\\\session-start.ps1\"",
      "timeoutSec": 3
    }
  ],
  "sessionEnd": [
    {
      "type": "command",
      "powershell": "& \"$HOME\\\\.copilot\\\\hooks\\\\ecc-memory\\\\session-end.ps1\"",
      "timeoutSec": 3
    }
  ]
}
```

- [ ] **Step 5: 跑一次综合观测并确认没有明显退化**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\HP\.copilot\diagnostics\measure-startup.ps1" -Runs 3
```

Expected:

```text
- 能输出 totalMs / hookStartMs / hookEndMs / resolveProjectMs / writeMetadataMs
- 不出现 hook timeout
- loginState.hasCachedLogin 为 true
```

## Self-Review

### Spec coverage

- 启动观测层：Task 1、Task 3
- 最小化优化层：Task 2、Task 4
- 登录稳态化：Task 4
- 验证与保留策略：Task 1、Task 3、Task 4

### Placeholder scan

- 未发现占位表达

### Type consistency

- 观测字段统一使用：`totalMs`、`hookStartMs`、`hookEndMs`、`resolveProjectMs`、`writeMetadataMs`
- 登录诊断字段统一使用：`hasCachedLogin`、`lastLoginHost`、`lastLoginUser`
