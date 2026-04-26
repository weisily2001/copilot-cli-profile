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
else {
  $reasons += '小任务默认不并发'
}

if ($mode -eq 'serial' -and $userIntentClear -and $budgetTier -ne 'small') {
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

if ($mode -eq 'serial') {
  $maxAgents = 1
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
