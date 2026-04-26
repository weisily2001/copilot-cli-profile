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

$smallParallelConflict = @{
  goal = '小任务但看起来存在三个独立子任务'
  independentSubtasks = 3
  phaseCount = 1
  sharedState = 'low'
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

$serialMedium = @{
  goal = '回答一个中等上下文但不适合并发的问题'
  independentSubtasks = 1
  phaseCount = 1
  sharedState = 'high'
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
$smallParallelConflictResult = & $scriptPath -ScenarioJson $smallParallelConflict | ConvertFrom-Json
$parallelResult = & $scriptPath -ScenarioJson $parallel | ConvertFrom-Json
$serialMediumResult = & $scriptPath -ScenarioJson $serialMedium | ConvertFrom-Json
$stagedResult = & $scriptPath -ScenarioJson $staged | ConvertFrom-Json

if ($smallResult.mode -ne 'serial') {
  throw "Expected serial, got $($smallResult.mode)"
}

if ($smallParallelConflictResult.mode -ne 'serial') {
  throw "Expected small task to stay serial, got $($smallParallelConflictResult.mode)"
}

if ($smallParallelConflictResult.budgetTier -ne 'small') {
  throw "Expected budgetTier small for small task, got $($smallParallelConflictResult.budgetTier)"
}

if ($smallParallelConflictResult.maxAgents -ne 1) {
  throw "Expected maxAgents 1 for small serial task, got $($smallParallelConflictResult.maxAgents)"
}

if ($parallelResult.mode -ne 'parallel-independent') {
  throw "Expected parallel-independent, got $($parallelResult.mode)"
}

if ($serialMediumResult.mode -ne 'serial') {
  throw "Expected serial, got $($serialMediumResult.mode)"
}

if ($serialMediumResult.maxAgents -ne 1) {
  throw "Expected maxAgents 1 for serial medium, got $($serialMediumResult.maxAgents)"
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

foreach ($contractPath in @(
  'C:\Users\HP\.copilot\agents\parallel-orchestrator.agent.md',
  'C:\Users\HP\.copilot\templates\project-bootstrap\.github\instructions\agent-orchestration.instructions.md',
  'C:\Users\HP\Desktop\copilot-ecc-bootstrap-test\.github\instructions\agent-orchestration.instructions.md'
)) {
  $content = Get-Content -Path $contractPath -Raw -Encoding UTF8
  foreach ($requiredField in @('目标', '边界', '输入材料', '预期产物', '禁止重复范围', '预算等级')) {
    if ($content -notmatch [regex]::Escape($requiredField)) {
      throw "Missing taskContracts field '$requiredField' in $contractPath"
    }
  }
}

Write-Host 'evaluate-agent-orchestration smoke PASS'
