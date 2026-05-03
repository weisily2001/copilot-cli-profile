param()

$ErrorActionPreference = 'Stop'
$copilotHome = 'C:\Users\HP\.copilot'
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
