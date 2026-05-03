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

# Validate minimal markdown skeletons
$memoryIndexContent = Get-Content -Path $memoryIndexPath -Raw -ErrorAction Stop
if (-not ($memoryIndexContent.Contains('# 全局记忆索引'))) {
  throw "memory-index.md missing heading: # 全局记忆索引"
}
foreach ($h in @('## 高频入口','## 技能入口')) {
  if (-not ($memoryIndexContent.Contains($h))) {
    throw "memory-index.md missing heading: $h"
  }
}

$globalFactsContent = Get-Content -Path $globalFactsPath -Raw -ErrorAction Stop
if (-not ($globalFactsContent.Contains('# 全局稳定事实'))) {
  throw "global-facts.md missing heading: # 全局稳定事实"
}
foreach ($h in @('## 文档治理','## 自动沉淀')) {
  if (-not ($globalFactsContent.Contains($h))) {
    throw "global-facts.md missing heading: $h"
  }
}

# Validate skill-registry structure
$registry = Get-Content -Path $skillRegistryPath -Raw | ConvertFrom-Json
if ($registry.version -ne 1) {
  throw "Expected skill-registry version 1, got '$($registry.version)'"
}
if (-not ($registry.PSObject.Properties.Name -contains 'skills')) {
  throw "skill-registry.json missing 'skills' property"
}
if (-not ($registry.skills -is [System.Array])) {
  throw "skill-registry.json 'skills' must be an array"
}

Write-Host 'global-memory-distillation smoke PASS'
