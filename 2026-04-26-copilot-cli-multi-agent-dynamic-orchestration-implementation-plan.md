# Copilot CLI 多 Agent 动态协同编排 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 Copilot CLI 增加一套可执行的多 agent 动态协同框架 v1，让主控 agent 能根据任务结构和 token 预算在“独立子任务并行”“同任务分阶段协同”“退回串行”之间做可解释决策。

**Architecture:** 方案只使用当前可控表面：全局指令、技能、代理定义、PowerShell 诊断脚本和项目模板。先用一个本地评估脚本把调度规则固化并可测试，再补一份并发编排技能和一个专用 orchestrator 代理，随后把调度约束写入全局指令，最后同步到模板与测试目录验证可见性。

**Tech Stack:** Markdown 指令与技能、Copilot CLI 自定义 agent、PowerShell 5+/7、JSON、Copilot CLI 交互命令

---

## File Structure

- Create: `C:\Users\HP\.copilot\diagnostics\evaluate-agent-orchestration.ps1` — 读取任务画像 JSON，输出调度模式、预算等级、最大并发数与停止条件
- Create: `C:\Users\HP\.copilot\diagnostics\evaluate-agent-orchestration-smoke.ps1` — 本地烟雾测试，覆盖“小任务串行 / 独立子任务并行 / 阶段协同”三类场景
- Create: `C:\Users\HP\.copilot\agent-orchestration-observability.md` — 记录调度输出字段、推荐观测指标与验证方式
- Create: `C:\Users\HP\.copilot\skills\parallel-orchestration\SKILL.md` — 并发编排技能，约束何时并发、何时串行、何时中途回收
- Create: `C:\Users\HP\.copilot\agents\parallel-orchestrator.agent.md` — 主控编排代理，输出任务拆分、子任务契约、汇总与降级计划
- Modify: `C:\Users\HP\.copilot\copilot-instructions.md` — 增加动态调度、预算门控和完成判定规则
- Create: `C:\Users\HP\.copilot\templates\project-bootstrap\.github\instructions\agent-orchestration.instructions.md` — 模板中的项目级并发编排规则
- Create: `C:\Users\HP\Desktop\copilot-ecc-bootstrap-test\.github\instructions\agent-orchestration.instructions.md` — 用于验证模板同步结果

说明：`C:\Users\HP\.copilot` 当前不是 Git 仓库，因此本计划统一使用“文件存在性检查 + 内容断言 + Copilot CLI 交互验证”作为完成信号，不单列 commit 步骤。

### Task 1: 新增调度评估脚本与烟雾测试

**Files:**
- Create: `C:\Users\HP\.copilot\diagnostics\evaluate-agent-orchestration.ps1`
- Create: `C:\Users\HP\.copilot\diagnostics\evaluate-agent-orchestration-smoke.ps1`
- Create: `C:\Users\HP\.copilot\agent-orchestration-observability.md`

- [ ] **Step 1: 先写会失败的烟雾测试**

Create:

```powershell
param()

$ErrorActionPreference = 'Stop'
$scriptPath = 'C:\Users\HP\.copilot\diagnostics\evaluate-agent-orchestration.ps1'

if (-not (Test-Path $scriptPath)) {
  throw "Missing script: $scriptPath"
}

$small = @{
  goal = '回答一个简单问题'
  independentSubtasks = 1
  phaseCount = 1
  sharedState = 'high'
  estimatedContextSize = 'small'
  userIntentClear = $true
} | ConvertTo-Json -Depth 3

$parallel = @{
  goal = '并行研究三个独立模块'
  independentSubtasks = 3
  phaseCount = 1
  sharedState = 'low'
  estimatedContextSize = 'medium'
  userIntentClear = $true
} | ConvertTo-Json -Depth 3

$staged = @{
  goal = '同一任务分研究、规划、验证三阶段'
  independentSubtasks = 1
  phaseCount = 3
  sharedState = 'medium'
  estimatedContextSize = 'large'
  userIntentClear = $true
} | ConvertTo-Json -Depth 3

$smallResult = & $scriptPath -ScenarioJson $small | ConvertFrom-Json
$parallelResult = & $scriptPath -ScenarioJson $parallel | ConvertFrom-Json
$stagedResult = & $scriptPath -ScenarioJson $staged | ConvertFrom-Json

if ($smallResult.mode -ne 'serial') {
  throw "Expected serial, got $($smallResult.mode)"
}

if ($parallelResult.mode -ne 'parallel-independent') {
  throw "Expected parallel-independent, got $($parallelResult.mode)"
}

if ($stagedResult.mode -ne 'parallel-staged') {
  throw "Expected parallel-staged, got $($stagedResult.mode)"
}

if ($null -eq $parallelResult.maxAgents) {
  throw 'Missing maxAgents'
}

if ($null -eq $parallelResult.budgetTier) {
  throw 'Missing budgetTier'
}

Write-Host 'evaluate-agent-orchestration smoke PASS'
```

- [ ] **Step 2: 运行烟雾测试并确认失败**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\HP\.copilot\diagnostics\evaluate-agent-orchestration-smoke.ps1"
```

Expected:

```text
Missing script: C:\Users\HP\.copilot\diagnostics\evaluate-agent-orchestration.ps1
```

- [ ] **Step 3: 写最小可用的调度评估脚本**

Create:

```powershell
param(
  [Parameter(Mandatory = $true)]
  [string]$ScenarioJson
)

$ErrorActionPreference = 'Stop'
$scenario = $ScenarioJson | ConvertFrom-Json

$independentSubtasks = [int]$scenario.independentSubtasks
$phaseCount = [int]$scenario.phaseCount
$sharedState = [string]$scenario.sharedState
$estimatedContextSize = [string]$scenario.estimatedContextSize
$userIntentClear = [bool]$scenario.userIntentClear

$mode = 'serial'
$budgetTier = 'small'
$maxAgents = 1
$reasons = @()

if (-not $userIntentClear) {
  $reasons += '用户意图未澄清，禁止并发'
}
elseif ($estimatedContextSize -eq 'large') {
  $budgetTier = 'large'
}
elseif ($estimatedContextSize -eq 'medium') {
  $budgetTier = 'medium'
}

if ($mode -eq 'serial' -and $userIntentClear) {
  if ($independentSubtasks -ge 2 -and $sharedState -eq 'low') {
    $mode = 'parallel-independent'
    $reasons += '独立子任务数量足够且共享状态低'
  }
  elseif ($phaseCount -ge 2 -and $sharedState -ne 'high') {
    $mode = 'parallel-staged'
    $reasons += '阶段边界清楚且可按阶段分工'
  }
  else {
    $reasons += '任务规模或共享状态不适合并发'
  }
}

switch ($budgetTier) {
  'small' { $maxAgents = 1 }
  'medium' { $maxAgents = 2 }
  'large' { $maxAgents = if ($mode -eq 'serial') { 1 } else { 3 } }
}

[ordered]@{
  mode = $mode
  budgetTier = $budgetTier
  maxAgents = $maxAgents
  stopConditions = @(
    '结果重叠率过高时停止扩散',
    '发现共享状态冲突时降级为串行',
    '汇总成本高于并发收益时终止并发'
  )
  reasons = $reasons
} | ConvertTo-Json -Depth 4
```

- [ ] **Step 4: 写编排观测说明文档**

Create:

```md
# 多 Agent 编排观测说明

## 调度评估脚本

- 脚本：`C:\Users\HP\.copilot\diagnostics\evaluate-agent-orchestration.ps1`
- 烟雾测试：`C:\Users\HP\.copilot\diagnostics\evaluate-agent-orchestration-smoke.ps1`

## 输出字段

- `mode`
- `budgetTier`
- `maxAgents`
- `stopConditions`
- `reasons`

## 推荐验收指标

- 总耗时
- 总 token 成本
- 重复工作率
- 一次性交付率

## 使用方式

```powershell
$scenario = @{
  goal = '并行研究三个独立模块'
  independentSubtasks = 3
  phaseCount = 1
  sharedState = 'low'
  estimatedContextSize = 'medium'
  userIntentClear = $true
} | ConvertTo-Json -Depth 3

powershell -ExecutionPolicy Bypass -File "C:\Users\HP\.copilot\diagnostics\evaluate-agent-orchestration.ps1" -ScenarioJson $scenario
```
```

- [ ] **Step 5: 重新运行烟雾测试并确认通过**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\HP\.copilot\diagnostics\evaluate-agent-orchestration-smoke.ps1"
```

Expected:

```text
evaluate-agent-orchestration smoke PASS
```

### Task 2: 新增并发编排技能

**Files:**
- Create: `C:\Users\HP\.copilot\skills\parallel-orchestration\SKILL.md`
- Test: `C:\Users\HP\.copilot\skills\parallel-orchestration\SKILL.md`

- [ ] **Step 1: 检查技能文件尚不存在**

Run:

```powershell
Test-Path "C:\Users\HP\.copilot\skills\parallel-orchestration\SKILL.md"
```

Expected:

```text
False
```

- [ ] **Step 2: 写并发编排技能**

Create:

```md
---
name: parallel-orchestration
description: 在复杂任务执行前，根据任务结构和 token 预算判断是否并行、采用独立子任务并行还是阶段协同。
---

使用该技能时：
1. 先确认用户目标是否清晰；不清晰则先澄清，不进入并发。
2. 先判断任务是“多个独立子任务”还是“同一任务的多个阶段”。
3. 小任务默认不并发；中任务最多 2 个 agent；大任务最多 3-4 个 agent，但必须共享状态低。
4. 独立子任务使用并行模式；阶段边界清楚时使用阶段协同；共享状态高时退回串行。
5. 每个子 agent 必须拿到统一任务契约：目标、边界、输入材料、预期产物、禁止重复范围、预算等级。
6. 若结果重叠率过高、共享状态冲突或汇总成本过高，则立即停止扩散并降级为串行收敛。
7. 并发完成不等于任务完成，最终必须由主控 agent 统一判断是否可交付。
```

- [ ] **Step 3: 运行内容检查**

Run:

```powershell
$checks = [pscustomobject]@{
  HasParallelRule = [bool](Select-String -Path "C:\Users\HP\.copilot\skills\parallel-orchestration\SKILL.md" -Pattern "小任务默认不并发")
  HasContractRule = [bool](Select-String -Path "C:\Users\HP\.copilot\skills\parallel-orchestration\SKILL.md" -Pattern "统一任务契约")
  HasFallbackRule = [bool](Select-String -Path "C:\Users\HP\.copilot\skills\parallel-orchestration\SKILL.md" -Pattern "降级为串行收敛")
}
$checks
```

Expected:

```text
HasParallelRule : True
HasContractRule : True
HasFallbackRule : True
```

### Task 3: 新增编排代理并固化全局规则

**Files:**
- Create: `C:\Users\HP\.copilot\agents\parallel-orchestrator.agent.md`
- Modify: `C:\Users\HP\.copilot\copilot-instructions.md`
- Test: `C:\Users\HP\.copilot\agents\parallel-orchestrator.agent.md`
- Test: `C:\Users\HP\.copilot\copilot-instructions.md`

- [ ] **Step 1: 先检查代理和全局规则缺失项**

Run:

```powershell
$checks = [pscustomobject]@{
  AgentExists = Test-Path "C:\Users\HP\.copilot\agents\parallel-orchestrator.agent.md"
  HasBudgetRule = [bool](Select-String -Path "C:\Users\HP\.copilot\copilot-instructions.md" -Pattern "小任务默认不并发")
  HasCompletionRule = [bool](Select-String -Path "C:\Users\HP\.copilot\copilot-instructions.md" -Pattern "并发完成不等于任务完成")
}
$checks
```

Expected: 至少两项为 `False`。

- [ ] **Step 2: 创建编排代理定义**

Create:

```md
---
name: parallel-orchestrator
description: 根据任务结构、共享状态和 token 预算，输出多 agent 调度方案、子任务契约、收敛与降级计划。
tools: ["read", "search"]
---

你是多 agent 编排代理。

职责：
- 判断任务是否值得并发
- 在 `parallel-independent`、`parallel-staged`、`serial` 之间做出选择
- 输出最大并发数、预算等级和停止条件
- 为每个子任务给出统一契约
- 说明结果如何汇总、何时降级为串行

输出结构：
1. mode
2. budgetTier
3. maxAgents
4. taskContracts
5. aggregationPlan
6. fallbackPlan
```

- [ ] **Step 3: 在全局工作内核中追加并发编排规则**

Append:

```md
18. 涉及复杂多步骤任务时，先做任务画像，再决定是否启用多 agent 并发。
19. 默认只并行独立子任务或阶段边界清楚的同任务分工；共享状态高或用户意图未澄清时退回串行。
20. 小任务默认不并发；中任务最多 2 个 agent；大任务最多 3-4 个 agent，并将 token 成本纳入决策。
21. 每个子 agent 启动前都要拿到统一任务契约：目标、边界、输入材料、预期产物、禁止重复范围、预算等级。
22. 若结果重叠率过高、共享状态冲突或汇总成本过高，主控 agent 必须停止扩散并降级为串行收敛。
23. 并发完成不等于任务完成；最终交付必须由主控 agent 统一汇总并判定可交付性。
```

- [ ] **Step 4: 重新运行规则检查**

Run:

```powershell
$checks = [pscustomobject]@{
  AgentExists = Test-Path "C:\Users\HP\.copilot\agents\parallel-orchestrator.agent.md"
  HasBudgetRule = [bool](Select-String -Path "C:\Users\HP\.copilot\copilot-instructions.md" -Pattern "小任务默认不并发")
  HasContractRule = [bool](Select-String -Path "C:\Users\HP\.copilot\copilot-instructions.md" -Pattern "统一任务契约")
  HasCompletionRule = [bool](Select-String -Path "C:\Users\HP\.copilot\copilot-instructions.md" -Pattern "并发完成不等于任务完成")
}
$checks
```

Expected:

```text
AgentExists       : True
HasBudgetRule     : True
HasContractRule   : True
HasCompletionRule : True
```

### Task 4: 同步模板并在测试目录验证可见性

**Files:**
- Create: `C:\Users\HP\.copilot\templates\project-bootstrap\.github\instructions\agent-orchestration.instructions.md`
- Create: `C:\Users\HP\Desktop\copilot-ecc-bootstrap-test\.github\instructions\agent-orchestration.instructions.md`
- Test: `C:\Users\HP\.copilot\templates\project-bootstrap\.github\instructions\agent-orchestration.instructions.md`
- Test: `C:\Users\HP\Desktop\copilot-ecc-bootstrap-test\.github\instructions\agent-orchestration.instructions.md`

- [ ] **Step 1: 检查模板指令文件尚不存在**

Run:

```powershell
$checks = [pscustomobject]@{
  TemplateExists = Test-Path "C:\Users\HP\.copilot\templates\project-bootstrap\.github\instructions\agent-orchestration.instructions.md"
  TestExists = Test-Path "C:\Users\HP\Desktop\copilot-ecc-bootstrap-test\.github\instructions\agent-orchestration.instructions.md"
}
$checks
```

Expected:

```text
TemplateExists : False
TestExists     : False
```

- [ ] **Step 2: 创建模板级并发编排指令**

Create:

```md
---
applyTo: "**"
---

处理当前项目的复杂任务时：
1. 先判断用户目标是否清晰；未澄清时先串行澄清，不启用并发。
2. 仅在独立子任务足够独立或阶段边界清楚时启用多 agent。
3. 小任务默认不并发；中任务最多 2 个 agent；大任务最多 3-4 个 agent。
4. 每个子 agent 必须拿到统一任务契约，避免重复劳动。
5. 若共享状态冲突、结果重叠率过高或汇总成本过高，则回退串行。
6. 并发完成不等于任务完成，最终由主控 agent 汇总交付。
```

- [ ] **Step 3: 复制模板指令到测试目录**

Run:

```powershell
Copy-Item -Path "C:\Users\HP\.copilot\templates\project-bootstrap\.github\instructions\agent-orchestration.instructions.md" -Destination "C:\Users\HP\Desktop\copilot-ecc-bootstrap-test\.github\instructions\agent-orchestration.instructions.md" -Force
```

Expected: 测试目录下出现同名指令文件。

- [ ] **Step 4: 运行模板与测试目录检查**

Run:

```powershell
$checks = [pscustomobject]@{
  TemplateExists = Test-Path "C:\Users\HP\.copilot\templates\project-bootstrap\.github\instructions\agent-orchestration.instructions.md"
  TestExists = Test-Path "C:\Users\HP\Desktop\copilot-ecc-bootstrap-test\.github\instructions\agent-orchestration.instructions.md"
  TemplateHasBudgetRule = [bool](Select-String -Path "C:\Users\HP\.copilot\templates\project-bootstrap\.github\instructions\agent-orchestration.instructions.md" -Pattern "小任务默认不并发")
  TestHasFallbackRule = [bool](Select-String -Path "C:\Users\HP\Desktop\copilot-ecc-bootstrap-test\.github\instructions\agent-orchestration.instructions.md" -Pattern "回退串行")
}
$checks
```

Expected:

```text
TemplateExists       : True
TestExists           : True
TemplateHasBudgetRule: True
TestHasFallbackRule  : True
```

- [ ] **Step 5: 进入测试目录并在 Copilot CLI 中验证技能、代理和指令可见**

Run:

```powershell
Set-Location "C:\Users\HP\Desktop\copilot-ecc-bootstrap-test"
copilot
```

Run in Copilot CLI:

```text
/skills reload
/skills list
/agent
/instructions
```

Expected:

```text
/skills list -> 能看到 parallel-orchestration
/agent -> 能看到 parallel-orchestrator
/instructions -> 能看到 agent-orchestration 相关规则
```

## Self-Review

### Spec coverage

- 主控 agent 任务画像：Task 1、Task 3
- 动态选择并发模式：Task 1、Task 3、Task 4
- token 预算门控：Task 1、Task 2、Task 3、Task 4
- 子 agent 统一任务契约：Task 2、Task 3、Task 4
- 结果汇总与冲突收敛：Task 1、Task 2、Task 3
- 基础观测指标：Task 1

### Placeholder scan

- 未保留任何未完成占位表达
- 每个代码步骤都给出了完整内容
- 每个验证步骤都给出了明确命令与预期结果

### Type consistency

- 调度模式统一使用：`serial`、`parallel-independent`、`parallel-staged`
- 预算等级统一使用：`small`、`medium`、`large`
- 统一任务契约名称统一使用：`task contract` / “统一任务契约”

