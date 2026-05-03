# Global Memory and Skill Distillation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 `C:\Users\HP\.copilot` 落地全局记忆分层、自动沉淀路由、skill 统一登记和索引刷新机制，同时保持现有 hooks、skills 和长期记忆文件稳定可回滚。

**Architecture:** 保留 `profile.md`、`preferences.json`、`corrections.md`、`session-state` 和现有 memory hooks 的职责不变，新增 `memory-index.md`、`global-facts.md`、`distillation-rules.json`、`skill-registry.json` 作为治理层，再通过 `hooks\ecc-memory\global-distillation.ps1` 在会话结束时执行“同步 + 可选路由”。语义性偏好/纠错继续由 `preference-learning`、`memory-handoff` 等技能负责写入长期层，session-end hook 负责把长期层和技能目录同步成统一索引。

**Tech Stack:** PowerShell 5+/7、Markdown、JSON、Copilot CLI hooks、现有 `.copilot\diagnostics` smoke 测试模式

**Execution Note:** 实施在隔离 worktree 中进行。计划中的文件目标仍按最终落点写成 `C:\Users\HP\.copilot\...`，但验证命令和 smoke 脚本必须以当前 worktree 为执行根，不能写死主工作区路径。

---

## File Structure

### Create

- `C:\Users\HP\.copilot\memory\global\memory-index.md` — L1 记忆索引，记录“场景/触发词 -> 文件/skill -> 简短备注”
- `C:\Users\HP\.copilot\memory\global\global-facts.md` — L2 全局稳定事实补充层
- `C:\Users\HP\.copilot\memory\global\distillation-rules.json` — 自动沉淀路由、禁止升级条件和索引刷新规则
- `C:\Users\HP\.copilot\skills\skill-registry.json` — L3 技能统一登记元数据
- `C:\Users\HP\.copilot\hooks\ecc-memory\global-distillation.ps1` — session-end 可调用的全局记忆同步/沉淀 helper
- `C:\Users\HP\.copilot\diagnostics\check-global-memory-distillation-smoke.ps1` — 验证文件结构、helper 行为和 session-end 集成

### Modify

- `C:\Users\HP\.copilot\hooks\ecc-memory\session-end.ps1` — 在 metadata 写入成功后调用 `global-distillation.ps1`
- `C:\Users\HP\.copilot\copilot-instructions.md` — 增加 L1/L2/L3/L4 读取顺序与自动沉淀规则
- `C:\Users\HP\.copilot\memory-governance.md` — 补充新增全局文件的职责边界
- `C:\Users\HP\.copilot\memory-lifecycle.md` — 补充路由类型、升级目标和“无法分类回退 L4”的规则
- `C:\Users\HP\.copilot\skills\memory-handoff\SKILL.md` — 增加索引刷新与长期层分流说明
- `C:\Users\HP\.copilot\skills\preference-learning\SKILL.md` — 增加写入长期层后同步刷新 L1 的要求
- `C:\Users\HP\.copilot\README.md` — 增加新文件说明、验证命令和回滚方式

### Test / Validate

- `C:\Users\HP\.copilot\diagnostics\check-global-memory-distillation-smoke.ps1`
- `C:\Users\HP\.copilot\diagnostics\hook-metrics-smoke.ps1`

---

### Task 1: 创建全局沉淀治理文件和会失败的 smoke

**Files:**
- Create: `C:\Users\HP\.copilot\diagnostics\check-global-memory-distillation-smoke.ps1`
- Create: `C:\Users\HP\.copilot\memory\global\memory-index.md`
- Create: `C:\Users\HP\.copilot\memory\global\global-facts.md`
- Create: `C:\Users\HP\.copilot\memory\global\distillation-rules.json`
- Create: `C:\Users\HP\.copilot\skills\skill-registry.json`

- [ ] **Step 1: 写出会失败的 smoke 脚本**

```powershell
param()

$ErrorActionPreference = 'Stop'
$copilotHome = Split-Path -Parent $PSScriptRoot
$memoryIndexPath = Join-Path $copilotHome 'memory\global\memory-index.md'
$globalFactsPath = Join-Path $copilotHome 'memory\global\global-facts.md'
$rulesPath = Join-Path $copilotHome 'memory\global\distillation-rules.json'
$skillRegistryPath = Join-Path $copilotHome 'skills\skill-registry.json'

foreach ($path in @($memoryIndexPath, $globalFactsPath, $rulesPath, $skillRegistryPath)) {
  if (-not (Test-Path $path)) {
    throw "Missing file: $path"
  }
}

$rules = Get-Content -Path $rulesPath -Raw | ConvertFrom-Json
foreach ($kind in @('stablePreference', 'correction', 'globalFact', 'skillSignal')) {
  if ($kind -notin $rules.routes.PSObject.Properties.Name) {
    throw "Missing route '$kind' in distillation rules"
  }
}

$registry = Get-Content -Path $skillRegistryPath -Raw | ConvertFrom-Json
if ($registry.version -ne 1) {
  throw "Expected skill-registry version 1, got '$($registry.version)'"
}

Write-Host 'global-memory-distillation smoke PASS'
```

- [ ] **Step 2: 运行 smoke，确认当前失败**

Run:

```powershell
Set-Location "C:\Users\HP\.copilot\.worktrees\global-memory-distillation-v1"
powershell -ExecutionPolicy Bypass -File ".\diagnostics\check-global-memory-distillation-smoke.ps1"
```

Expected: FAIL with `Missing file` because the new governance files do not exist yet in the current worktree.

- [ ] **Step 3: 写最小实现：新增 4 个治理文件**

`C:\Users\HP\.copilot\memory\global\memory-index.md`

```md
# 全局记忆索引

## 高频入口

- 稳定偏好 -> `memory\global\profile.md` -> 先看口语化偏好摘要
- 结构化偏好 -> `memory\global\preferences.json` -> 机器可读键值优先
- 稳定纠错 -> `memory\global\corrections.md` -> 先看触发场景与避免事项
- 全局稳定事实 -> `memory\global\global-facts.md` -> 仅包含长期有效事实

## 技能入口

- 待 `skill-registry.json` 初始化后由同步脚本自动刷新
```

`C:\Users\HP\.copilot\memory\global\global-facts.md`

```md
# 全局稳定事实

## 文档治理

- 全局能力、全局配置、全局流程文档统一写入 `C:\Users\HP\.copilot`

## 自动沉淀

- 全局自动沉淀的治理规则在本目录维护，后续由 hooks 接入执行
```

`C:\Users\HP\.copilot\memory\global\distillation-rules.json`

```json
{
  "version": 1,
  "routes": {
    "stablePreference": {
      "targets": [
        "memory\\global\\profile.md",
        "memory\\global\\preferences.json",
        "memory\\global\\memory-index.md"
      ],
      "dedupeBy": "key"
    },
    "correction": {
      "targets": [
        "memory\\global\\corrections.md",
        "memory\\global\\memory-index.md"
      ],
      "dedupeBy": "scenario"
    },
    "globalFact": {
      "targets": [
        "memory\\global\\global-facts.md",
        "memory\\global\\memory-index.md"
      ],
      "dedupeBy": "summary"
    },
    "skillSignal": {
      "targets": [
        "skills\\skill-registry.json",
        "memory\\global\\memory-index.md"
      ],
      "dedupeBy": "name"
    }
  },
  "forbiddenSignals": [
    "临时",
    "一次性",
    "调试输出",
    "未验证",
    "猜测"
  ],
  "fallbackRoute": "L4"
}
```

`C:\Users\HP\.copilot\skills\skill-registry.json`

```json
{
  "version": 1,
  "skills": []
}
```

- [ ] **Step 4: 运行 smoke，确认基础结构通过**

Run:

```powershell
Set-Location "C:\Users\HP\.copilot\.worktrees\global-memory-distillation-v1"
powershell -ExecutionPolicy Bypass -File ".\diagnostics\check-global-memory-distillation-smoke.ps1"
```

Expected: PASS with `global-memory-distillation smoke PASS`

- [ ] **Step 5: 提交**

```bash
git -C C:\Users\HP\.copilot\.worktrees\global-memory-distillation-v1 add diagnostics/check-global-memory-distillation-smoke.ps1 memory/global/memory-index.md memory/global/global-facts.md memory/global/distillation-rules.json skills/skill-registry.json
git -C C:\Users\HP\.copilot\.worktrees\global-memory-distillation-v1 commit -m "新增全局记忆沉淀治理骨架"
```

### Task 2: 为现有全局 skills 建立统一 registry，并刷新 L1 索引

**Files:**
- Modify: `C:\Users\HP\.copilot\skills\skill-registry.json`
- Modify: `C:\Users\HP\.copilot\memory\global\memory-index.md`
- Test: `C:\Users\HP\.copilot\diagnostics\check-global-memory-distillation-smoke.ps1`

- [ ] **Step 1: 扩展 smoke，先让它对现有 5 个全局 skills 失败**

在 `check-global-memory-distillation-smoke.ps1` 末尾的 `$registry` 断言后追加：

```powershell
$expectedSkills = @(
  'ecc-verification-before-completion',
  'memory-handoff',
  'parallel-orchestration',
  'preference-learning',
  'research-first'
)

$skillNames = @($registry.skills | ForEach-Object { $_.name })
foreach ($name in $expectedSkills) {
  if ($name -notin $skillNames) {
    throw "Missing skill '$name' in skill registry"
  }
}

$memoryIndexContent = Get-Content -Path $memoryIndexPath -Raw
foreach ($name in @('memory-handoff', 'preference-learning', 'research-first')) {
  if ($memoryIndexContent -notmatch [regex]::Escape($name)) {
    throw "Expected memory index to mention '$name'"
  }
}
```

- [ ] **Step 2: 运行 smoke，确认当前失败**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\HP\.copilot\diagnostics\check-global-memory-distillation-smoke.ps1"
```

Expected: FAIL with `Missing skill` because the registry is still empty.

- [ ] **Step 3: 写最小实现：填充 registry 和 L1 索引**

`C:\Users\HP\.copilot\skills\skill-registry.json`

```json
{
  "version": 1,
  "skills": [
    {
      "name": "ecc-verification-before-completion",
      "purpose": "在宣称任务完成前回读目标、核对改动面并说明实际结果。",
      "triggers": ["完成前验证", "收尾核对", "结果复核"],
      "scope": "global",
      "stability": "stable",
      "relatedDocs": ["memory-lifecycle.md"],
      "relatedMemory": ["memory\\global\\memory-index.md"]
    },
    {
      "name": "memory-handoff",
      "purpose": "在任务结束或窗口切换前压缩项目记忆并维护 handoff/state/decisions。",
      "triggers": ["handoff", "跨窗口", "跨天续做"],
      "scope": "global",
      "stability": "stable",
      "relatedDocs": ["memory-governance.md", "memory-lifecycle.md"],
      "relatedMemory": ["memory\\global\\memory-index.md", "memory\\global\\global-facts.md"]
    },
    {
      "name": "parallel-orchestration",
      "purpose": "在复杂任务执行前决定是否并行、如何拆分子任务和如何收敛。",
      "triggers": ["并行", "多 agent", "任务拆分"],
      "scope": "global",
      "stability": "stable",
      "relatedDocs": ["copilot-instructions.md"],
      "relatedMemory": ["memory\\global\\memory-index.md"]
    },
    {
      "name": "preference-learning",
      "purpose": "在用户明确表达稳定偏好或纠错时，把规则升级到全局长期层。",
      "triggers": ["稳定偏好", "以后都这样", "不是这个意思"],
      "scope": "global",
      "stability": "stable",
      "relatedDocs": ["memory-lifecycle.md"],
      "relatedMemory": ["memory\\global\\profile.md", "memory\\global\\preferences.json", "memory\\global\\corrections.md"]
    },
    {
      "name": "research-first",
      "purpose": "实现前先研究目录、关键文件、已有模式和外部文档。",
      "triggers": ["先研究", "上下文", "已有模式", "官方文档"],
      "scope": "global",
      "stability": "stable",
      "relatedDocs": ["copilot-instructions.md"],
      "relatedMemory": ["memory\\global\\memory-index.md"]
    }
  ]
}
```

`C:\Users\HP\.copilot\memory\global\memory-index.md`

```md
# 全局记忆索引

## 高频入口

- 稳定偏好 -> `memory\global\profile.md` -> 先看口语化偏好摘要
- 结构化偏好 -> `memory\global\preferences.json` -> 机器可读键值优先
- 稳定纠错 -> `memory\global\corrections.md` -> 先看触发场景与避免事项
- 全局稳定事实 -> `memory\global\global-facts.md` -> 只保留长期有效事实

## 技能入口

- `memory-handoff` -> `skills\memory-handoff\SKILL.md` -> 跨窗口交接、跨天续做、短期状态压缩
- `preference-learning` -> `skills\preference-learning\SKILL.md` -> 稳定偏好、明确纠错升级
- `research-first` -> `skills\research-first\SKILL.md` -> 实现前先研究上下文
- `parallel-orchestration` -> `skills\parallel-orchestration\SKILL.md` -> 大任务拆分与收敛
- `ecc-verification-before-completion` -> `skills\ecc-verification-before-completion\SKILL.md` -> 结果交付前核对目标与实际结果
```

- [ ] **Step 4: 运行 smoke，确认 registry 和索引通过**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\HP\.copilot\diagnostics\check-global-memory-distillation-smoke.ps1"
```

Expected: PASS with `global-memory-distillation smoke PASS`

- [ ] **Step 5: 提交**

```bash
git -C C:\Users\HP\.copilot add skills/skill-registry.json memory/global/memory-index.md diagnostics/check-global-memory-distillation-smoke.ps1
git -C C:\Users\HP\.copilot commit -m "登记全局技能并初始化记忆索引"
```

### Task 3: 实现全局沉淀 helper，并支持路由 + 索引刷新

**Files:**
- Create: `C:\Users\HP\.copilot\hooks\ecc-memory\global-distillation.ps1`
- Modify: `C:\Users\HP\.copilot\diagnostics\check-global-memory-distillation-smoke.ps1`
- Test: `C:\Users\HP\.copilot\diagnostics\check-global-memory-distillation-smoke.ps1`

- [ ] **Step 1: 先把 smoke 扩展到 helper 直接调用场景**

在 `check-global-memory-distillation-smoke.ps1` 末尾追加：

```powershell
$helperPath = Join-Path $copilotHome 'hooks\ecc-memory\global-distillation.ps1'
if (-not (Test-Path $helperPath)) {
  throw "Missing helper: $helperPath"
}

$tempRoot = Join-Path $env:TEMP 'global-memory-distillation-smoke'
$tempCopilotHome = Join-Path $tempRoot '.copilot'
try {
  New-Item -ItemType Directory -Force -Path (Join-Path $tempCopilotHome 'memory\global'), (Join-Path $tempCopilotHome 'skills') | Out-Null
  Copy-Item -Path $memoryIndexPath -Destination (Join-Path $tempCopilotHome 'memory\global\memory-index.md') -Force
  Copy-Item -Path $globalFactsPath -Destination (Join-Path $tempCopilotHome 'memory\global\global-facts.md') -Force
  Copy-Item -Path $rulesPath -Destination (Join-Path $tempCopilotHome 'memory\global\distillation-rules.json') -Force
  Copy-Item -Path $skillRegistryPath -Destination (Join-Path $tempCopilotHome 'skills\skill-registry.json') -Force
  Copy-Item -Path (Join-Path $copilotHome 'memory\global\profile.md') -Destination (Join-Path $tempCopilotHome 'memory\global\profile.md') -Force
  Copy-Item -Path (Join-Path $copilotHome 'memory\global\preferences.json') -Destination (Join-Path $tempCopilotHome 'memory\global\preferences.json') -Force
  Copy-Item -Path (Join-Path $copilotHome 'memory\global\corrections.md') -Destination (Join-Path $tempCopilotHome 'memory\global\corrections.md') -Force
  Copy-Item -Path $helperPath -Destination (Join-Path $tempCopilotHome 'hooks\ecc-memory\global-distillation.ps1') -Force

  . (Join-Path $tempCopilotHome 'hooks\ecc-memory\global-distillation.ps1')
  $candidates = @(
    [pscustomobject]@{ kind = 'globalFact'; summary = '全局 skill registry 是长期治理入口'; index = 'skill registry' },
    [pscustomobject]@{ kind = 'skillSignal'; name = 'memory-handoff'; purpose = '跨窗口连续性'; triggers = @('handoff', '跨窗口'); scope = 'global'; stability = 'stable' }
  )

  Invoke-GlobalMemoryDistillation -CopilotHome $tempCopilotHome -Candidates $candidates | Out-Null

  $tempFacts = Get-Content -Path (Join-Path $tempCopilotHome 'memory\global\global-facts.md') -Raw
  if ($tempFacts -notmatch 'skill registry') {
    throw 'Expected helper to append global fact'
  }
}
finally {
  if (Test-Path $tempRoot) {
    Remove-Item $tempRoot -Recurse -Force
  }
}
```

- [ ] **Step 2: 运行 smoke，确认当前失败**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\HP\.copilot\diagnostics\check-global-memory-distillation-smoke.ps1"
```

Expected: FAIL with `Missing helper` because `global-distillation.ps1` does not exist yet.

- [ ] **Step 3: 写最小实现：global-distillation.ps1**

```powershell
$ErrorActionPreference = 'Stop'

function Get-DistillationPaths {
  param([string]$CopilotHome)

  return [pscustomobject]@{
    CopilotHome       = $CopilotHome
    MemoryIndexPath   = Join-Path $CopilotHome 'memory\global\memory-index.md'
    GlobalFactsPath   = Join-Path $CopilotHome 'memory\global\global-facts.md'
    ProfilePath       = Join-Path $CopilotHome 'memory\global\profile.md'
    PreferencesPath   = Join-Path $CopilotHome 'memory\global\preferences.json'
    CorrectionsPath   = Join-Path $CopilotHome 'memory\global\corrections.md'
    RulesPath         = Join-Path $CopilotHome 'memory\global\distillation-rules.json'
    SkillRegistryPath = Join-Path $CopilotHome 'skills\skill-registry.json'
    SkillsRoot        = Join-Path $CopilotHome 'skills'
  }
}

function Read-JsonFile {
  param([string]$Path)

  if (-not (Test-Path $Path)) {
    throw "Missing JSON file: $Path"
  }

  return Get-Content -Path $Path -Raw | ConvertFrom-Json
}

function Write-JsonFile {
  param(
    [string]$Path,
    [object]$Value
  )

  $parent = Split-Path $Path -Parent
  if (-not [string]::IsNullOrWhiteSpace($parent)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }

  $Value | ConvertTo-Json -Depth 8 | Set-Content -Path $Path -Encoding UTF8
}

function Add-UniqueLine {
  param(
    [string]$Path,
    [string]$Line
  )

  $content = if (Test-Path $Path) { Get-Content -Path $Path -Raw } else { '' }
  if ($content -notmatch [regex]::Escape($Line)) {
    Add-Content -Path $Path -Value $Line
  }
}

function Sync-MemoryIndex {
  param(
    [pscustomobject]$Paths,
    [object]$Registry
  )

  $lines = @(
    '# 全局记忆索引',
    '',
    '## 高频入口',
    '',
    '- 稳定偏好 -> `memory\global\profile.md` -> 先看口语化偏好摘要',
    '- 结构化偏好 -> `memory\global\preferences.json` -> 机器可读键值优先',
    '- 稳定纠错 -> `memory\global\corrections.md` -> 先看触发场景与避免事项',
    '- 全局稳定事实 -> `memory\global\global-facts.md` -> 只保留长期有效事实',
    '',
    '## 技能入口',
    ''
  )

  foreach ($skill in @($Registry.skills)) {
    $lines += "- ``$($skill.name)`` -> `skills\$($skill.name)\SKILL.md` -> $($skill.purpose)"
  }

  $lines | Set-Content -Path $Paths.MemoryIndexPath -Encoding UTF8
}

function Invoke-GlobalMemoryDistillation {
  param(
    [string]$CopilotHome = (Join-Path $HOME '.copilot'),
    [array]$Candidates = @()
  )

  $paths = Get-DistillationPaths -CopilotHome $CopilotHome
  $registry = Read-JsonFile -Path $paths.SkillRegistryPath

  foreach ($candidate in @($Candidates)) {
    switch ($candidate.kind) {
      'globalFact' {
        Add-UniqueLine -Path $paths.GlobalFactsPath -Line "- $($candidate.summary)"
      }
      'skillSignal' {
        $existing = @($registry.skills | Where-Object { $_.name -eq $candidate.name })
        if ($existing.Count -eq 0) {
          $registry.skills += [pscustomobject]@{
            name          = $candidate.name
            purpose       = $candidate.purpose
            triggers      = @($candidate.triggers)
            scope         = $candidate.scope
            stability     = $candidate.stability
            relatedDocs   = @()
            relatedMemory = @('memory\global\memory-index.md')
          }
        }
      }
    }
  }

  Write-JsonFile -Path $paths.SkillRegistryPath -Value $registry
  Sync-MemoryIndex -Paths $paths -Registry $registry

  return [pscustomobject]@{
    updatedRegistry = $paths.SkillRegistryPath
    updatedIndex    = $paths.MemoryIndexPath
    updatedFacts    = $paths.GlobalFactsPath
  }
}
```

- [ ] **Step 4: 运行 smoke，确认 helper 路由和索引刷新通过**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\HP\.copilot\diagnostics\check-global-memory-distillation-smoke.ps1"
```

Expected: PASS with `global-memory-distillation smoke PASS`

- [ ] **Step 5: 提交**

```bash
git -C C:\Users\HP\.copilot add hooks/ecc-memory/global-distillation.ps1 diagnostics/check-global-memory-distillation-smoke.ps1
git -C C:\Users\HP\.copilot commit -m "新增全局记忆沉淀 helper"
```

### Task 4: 在 session-end hook 中接入全局沉淀 helper

**Files:**
- Modify: `C:\Users\HP\.copilot\hooks\ecc-memory\session-end.ps1`
- Modify: `C:\Users\HP\.copilot\diagnostics\check-global-memory-distillation-smoke.ps1`
- Test: `C:\Users\HP\.copilot\diagnostics\check-global-memory-distillation-smoke.ps1`
- Test: `C:\Users\HP\.copilot\diagnostics\hook-metrics-smoke.ps1`

- [ ] **Step 1: 扩展 smoke，先让 session-end 集成断言失败**

在 `check-global-memory-distillation-smoke.ps1` 的 `finally` 之前追加：

```powershell
$tempHomeRoot = Join-Path $env:TEMP 'global-memory-distillation-hook-home'
$tempCopilotHome = Join-Path $tempHomeRoot '.copilot'
$projectsRoot = Join-Path $tempHomeRoot 'projects'
$projectDir = Join-Path $projectsRoot 'global-memory-distillation-smoke'
$fixtureRoot = Join-Path $tempHomeRoot 'fixture'
$cachePath = Join-Path $tempHomeRoot 'project-context-cache.json'
$metricsPath = Join-Path $tempHomeRoot 'hook-metrics.jsonl'

try {
  New-Item -ItemType Directory -Force -Path $tempCopilotHome, $projectsRoot, $projectDir, $fixtureRoot | Out-Null
  Copy-Item -Path (Join-Path $copilotHome 'hooks') -Destination $tempCopilotHome -Recurse -Force
  Copy-Item -Path (Join-Path $copilotHome 'memory') -Destination $tempCopilotHome -Recurse -Force
  Copy-Item -Path (Join-Path $copilotHome 'skills') -Destination $tempCopilotHome -Recurse -Force

  @'
{
  "projectKey": "global-memory-distillation-smoke",
  "projectRoot": "__ROOT__"
}
'@.Replace('__ROOT__', $fixtureRoot.Replace('\', '\\')) | Set-Content -Path (Join-Path $projectDir 'project.json') -Encoding UTF8

  $oldHome = $env:HOME
  $env:HOME = $tempHomeRoot
  $env:COPILOT_ECC_MEMORY_PROJECTS_ROOT = $projectsRoot
  $env:COPILOT_ECC_MEMORY_CACHE_PATH = $cachePath
  $env:COPILOT_ECC_MEMORY_METRICS_PATH = $metricsPath

  Push-Location $fixtureRoot
  try {
    $sessionEndOutput = & (Join-Path $tempCopilotHome 'hooks\ecc-memory\session-end.ps1') 2>&1
  }
  finally {
    Pop-Location
  }

  if (-not ($sessionEndOutput -match '\{"continue":true\}')) {
    throw 'Expected session-end hook to continue after distillation'
  }

  $indexAfterHook = Get-Content -Path (Join-Path $tempCopilotHome 'memory\global\memory-index.md') -Raw
  if ($indexAfterHook -notmatch 'memory-handoff') {
    throw 'Expected session-end hook to refresh memory index'
  }

  $env:HOME = $oldHome
}
finally {
  Remove-Item Env:\COPILOT_ECC_MEMORY_PROJECTS_ROOT -ErrorAction SilentlyContinue
  Remove-Item Env:\COPILOT_ECC_MEMORY_CACHE_PATH -ErrorAction SilentlyContinue
  Remove-Item Env:\COPILOT_ECC_MEMORY_METRICS_PATH -ErrorAction SilentlyContinue
  if (Test-Path $tempHomeRoot) {
    Remove-Item $tempHomeRoot -Recurse -Force
  }
}
```

- [ ] **Step 2: 运行 smoke，确认当前失败**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\HP\.copilot\diagnostics\check-global-memory-distillation-smoke.ps1"
```

Expected: FAIL because `session-end.ps1` does not call the new helper yet.

- [ ] **Step 3: 在 session-end.ps1 中接入 helper，且失败不影响 continue**

把 `Write-LastSessionMetadata` 成功分支扩成下面结构：

```powershell
      try {
        $writeMetadataMs = Write-LastSessionMetadata -ProjectKey $project.ProjectKey -ProjectRoot $project.ProjectRoot -ProjectDir $project.ProjectDir -EventName 'sessionEnd'

        try {
          . (Join-Path $HOME '.copilot\hooks\ecc-memory\global-distillation.ps1')
          Invoke-GlobalMemoryDistillation -CopilotHome (Join-Path $HOME '.copilot') | Out-Null
        }
        catch {
          [Console]::Error.WriteLine("Warning: session-end distillation skipped: $($_.Exception.Message)")
        }

        $status = 'success'
      }
      catch {
        $status = 'metadataWriteFailed'
        $errorMessage = Get-StableLifecycleErrorMessage -Status $status -EventName 'sessionEnd' -ProjectKey $project.ProjectKey -CurrentPath $currentPath
        [Console]::Error.WriteLine("Warning: session-end hook failed: $($_.Exception.Message)")
      }
```

- [ ] **Step 4: 运行 session-end 集成 smoke 和现有 hook 回归**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\HP\.copilot\diagnostics\check-global-memory-distillation-smoke.ps1"
powershell -ExecutionPolicy Bypass -File "C:\Users\HP\.copilot\diagnostics\hook-metrics-smoke.ps1"
```

Expected:

```text
global-memory-distillation smoke PASS
hook-metrics smoke PASS
```

- [ ] **Step 5: 提交**

```bash
git -C C:\Users\HP\.copilot add hooks/ecc-memory/session-end.ps1 diagnostics/check-global-memory-distillation-smoke.ps1
git -C C:\Users\HP\.copilot commit -m "在 session-end 中接入全局沉淀同步"
```

### Task 5: 更新全局文档与技能说明，并完成回归

**Files:**
- Modify: `C:\Users\HP\.copilot\copilot-instructions.md`
- Modify: `C:\Users\HP\.copilot\memory-governance.md`
- Modify: `C:\Users\HP\.copilot\memory-lifecycle.md`
- Modify: `C:\Users\HP\.copilot\skills\memory-handoff\SKILL.md`
- Modify: `C:\Users\HP\.copilot\skills\preference-learning\SKILL.md`
- Modify: `C:\Users\HP\.copilot\README.md`
- Test: `C:\Users\HP\.copilot\diagnostics\check-global-memory-distillation-smoke.ps1`
- Test: `C:\Users\HP\.copilot\diagnostics\hook-metrics-smoke.ps1`

- [ ] **Step 1: 先写一个会失败的文档校验命令**

Run:

```powershell
$checks = [pscustomobject]@{
  InstructionsHasIndexRule = [bool](Select-String -Path "C:\Users\HP\.copilot\copilot-instructions.md" -Pattern "memory-index.md")
  GovernanceHasRegistry = [bool](Select-String -Path "C:\Users\HP\.copilot\memory-governance.md" -Pattern "skill-registry.json")
  LifecycleHasGlobalFact = [bool](Select-String -Path "C:\Users\HP\.copilot\memory-lifecycle.md" -Pattern "global-facts.md")
  HandoffHasIndexRefresh = [bool](Select-String -Path "C:\Users\HP\.copilot\skills\memory-handoff\SKILL.md" -Pattern "memory-index")
  PreferenceHasIndexRefresh = [bool](Select-String -Path "C:\Users\HP\.copilot\skills\preference-learning\SKILL.md" -Pattern "memory-index")
  ReadmeHasSmokeCommand = [bool](Select-String -Path "C:\Users\HP\.copilot\README.md" -Pattern "check-global-memory-distillation-smoke.ps1")
}
$checks
```

Expected: 至少 4 项为 `False`。

- [ ] **Step 2: 更新全局文档与技能说明**

`C:\Users\HP\.copilot\copilot-instructions.md`

```md
24. 全局记忆读取优先级调整为：先读 `memory\global\memory-index.md`，再按索引命中目标文件或 skill；无命中时才回退到全量搜索。
25. 全局自动沉淀仅在满足“已验证、可复用、跨任务仍有价值、不是临时状态”时升级到长期层；无法明确分类时回退到 L4。
```

`C:\Users\HP\.copilot\memory-governance.md`

```md
## 全局记忆治理文件

- `memory\global\memory-index.md`：L1 索引层
- `memory\global\global-facts.md`：L2 稳定事实补充层
- `memory\global\distillation-rules.json`：自动沉淀路由规则
- `skills\skill-registry.json`：L3 技能统一登记层
```

`C:\Users\HP\.copilot\memory-lifecycle.md`

```md
## 6. 全局自动沉淀路由

- 稳定偏好 → `profile.md` / `preferences.json`
- 明确纠错 → `corrections.md`
- 全局稳定事实 → `global-facts.md`
- skill / SOP 线索 → `skill-registry.json`
- 路由完成后同步刷新 `memory-index.md`
- 无法明确分类时回退到 L4，不升级
```

`C:\Users\HP\.copilot\skills\memory-handoff\SKILL.md`

```md
9. 若全局长期层发生变化，任务收尾前同步刷新 `C:\Users\HP\.copilot\memory\global\memory-index.md` 与 `C:\Users\HP\.copilot\skills\skill-registry.json`。
```

`C:\Users\HP\.copilot\skills\preference-learning\SKILL.md`

```md
7. 稳定偏好或明确纠错写入长期层后，同步刷新 `C:\Users\HP\.copilot\memory\global\memory-index.md`，确保后续任务先命中索引。
```

`C:\Users\HP\.copilot\README.md`

~~~md
## 全局记忆治理验证

运行全局记忆沉淀 smoke：

~~~powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\HP\.copilot\diagnostics\check-global-memory-distillation-smoke.ps1"
~~~

运行 hook 回归 smoke：

~~~powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\HP\.copilot\diagnostics\hook-metrics-smoke.ps1"
~~~
~~~

- [ ] **Step 3: 运行文档校验命令，确认全部命中**

Run:

```powershell
$checks = [pscustomobject]@{
  InstructionsHasIndexRule = [bool](Select-String -Path "C:\Users\HP\.copilot\copilot-instructions.md" -Pattern "memory-index.md")
  GovernanceHasRegistry = [bool](Select-String -Path "C:\Users\HP\.copilot\memory-governance.md" -Pattern "skill-registry.json")
  LifecycleHasGlobalFact = [bool](Select-String -Path "C:\Users\HP\.copilot\memory-lifecycle.md" -Pattern "global-facts.md")
  HandoffHasIndexRefresh = [bool](Select-String -Path "C:\Users\HP\.copilot\skills\memory-handoff\SKILL.md" -Pattern "memory-index")
  PreferenceHasIndexRefresh = [bool](Select-String -Path "C:\Users\HP\.copilot\skills\preference-learning\SKILL.md" -Pattern "memory-index")
  ReadmeHasSmokeCommand = [bool](Select-String -Path "C:\Users\HP\.copilot\README.md" -Pattern "check-global-memory-distillation-smoke.ps1")
}
$checks
```

Expected:

```text
InstructionsHasIndexRule : True
GovernanceHasRegistry    : True
LifecycleHasGlobalFact   : True
HandoffHasIndexRefresh   : True
PreferenceHasIndexRefresh: True
ReadmeHasSmokeCommand    : True
```

- [ ] **Step 4: 运行最终回归**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\HP\.copilot\diagnostics\check-global-memory-distillation-smoke.ps1"
powershell -ExecutionPolicy Bypass -File "C:\Users\HP\.copilot\diagnostics\hook-metrics-smoke.ps1"
git -C "C:\Users\HP\.copilot" --no-pager diff --stat
```

Expected:

```text
global-memory-distillation smoke PASS
hook-metrics smoke PASS
```

并且 `git diff --stat` 只显示本计划涉及的治理文件、hook 文件、skill 文件和文档文件。

- [ ] **Step 5: 提交**

```bash
git -C C:\Users\HP\.copilot add copilot-instructions.md memory-governance.md memory-lifecycle.md skills/memory-handoff/SKILL.md skills/preference-learning/SKILL.md README.md
git -C C:\Users\HP\.copilot commit -m "补齐全局记忆沉淀文档与技能约束"
```

---

## Self-Review

### Spec coverage

- L1 索引层：Task 1、Task 2、Task 3、Task 4
- L2 稳定事实层：Task 1、Task 3、Task 5
- L3 技能登记层：Task 1、Task 2、Task 3、Task 5
- L4 会话归档到长期层的升级边界：Task 3、Task 4、Task 5
- hooks 失败不影响正常会话：Task 4
- 全局文档与技能同步：Task 5

### Placeholder scan

- 没有 `TODO`、`TBD`、`implement later` 一类占位词。
- 每个代码步骤都给了明确文件内容或插入片段。
- 每个验证步骤都给了可执行命令和预期结果。

### Type consistency

- 统一使用 `memory-index.md`、`global-facts.md`、`distillation-rules.json`、`skill-registry.json`
- 候选类型统一为 `stablePreference`、`correction`、`globalFact`、`skillSignal`
- helper 入口统一为 `Invoke-GlobalMemoryDistillation`

