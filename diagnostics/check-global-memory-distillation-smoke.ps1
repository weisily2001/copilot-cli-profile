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

$rules = Get-Content -Path $rulesPath -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($kind in @('stablePreference', 'correction', 'globalFact', 'skillSignal')) {
  if ($kind -notin $rules.routes.PSObject.Properties.Name) {
    throw "Missing route '$kind' in distillation rules"
  }
}

# Validate minimal markdown skeletons
$bm1 = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('IyDlhajlsYDorrDlv4bntKLlvJU='))
$bm2 = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('IyMg6auY6aKR5YWl5Y+j'))
$bm3 = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('IyMg5oqA6IO95YWl5Y+j'))
$bm4 = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('IyDlhajlsYDnqLPlrprkuovlrp4='))
$bm5 = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('IyMg5paH5qGj5rK755CG'))
$bm6 = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('IyMg6Ieq5Yqo5rKJ5reA'))

$memoryIndexContent = Get-Content -Path $memoryIndexPath -Raw -Encoding UTF8 -ErrorAction Stop
if (-not ($memoryIndexContent.Contains($bm1))) {
  throw "memory-index.md missing heading: $bm1"
}
foreach ($h in @($bm2,$bm3)) {
  if (-not ($memoryIndexContent.Contains($h))) {
    throw "memory-index.md missing heading: $h"
  }
}

$globalFactsContent = Get-Content -Path $globalFactsPath -Raw -Encoding UTF8 -ErrorAction Stop
if (-not ($globalFactsContent.Contains($bm4))) {
  throw "global-facts.md missing heading: $bm4"
}
foreach ($h in @($bm5,$bm6)) {
  if (-not ($globalFactsContent.Contains($h))) {
    throw "global-facts.md missing heading: $h"
  }
}

# Validate skill-registry structure
$registry = Get-Content -Path $skillRegistryPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
if ($registry.version -ne 1) {
  throw "Expected skill-registry version 1, got '$($registry.version)'"
}
if (-not ($registry.PSObject.Properties.Name -contains 'skills')) {
  throw "skill-registry.json missing 'skills' property"
}
if (-not ($registry.skills -is [System.Array])) {
  throw "skill-registry.json 'skills' must be an array"
}

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

foreach ($name in @('memory-handoff', 'preference-learning', 'research-first')) {
  if ($memoryIndexContent -notmatch [regex]::Escape($name)) {
    throw "Expected memory index to mention '$name'"
  }
}

$helperPath = Join-Path $copilotHome 'hooks\ecc-memory\global-distillation.ps1'
if (-not (Test-Path $helperPath)) {
  throw "Missing helper: $helperPath"
}

$tempRoot = Join-Path $env:TEMP 'global-memory-distillation-smoke'
$tempCopilotHome = Join-Path $tempRoot '.copilot'

try {
  New-Item -ItemType Directory -Force -Path (Join-Path $tempCopilotHome 'memory\global'), (Join-Path $tempCopilotHome 'skills'), (Join-Path $tempCopilotHome 'hooks\ecc-memory') | Out-Null
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
    [pscustomobject]@{
      kind    = 'stablePreference'
      key     = 'distillationSmokeMode'
      value   = 'enabled'
      summary = '全局沉淀 smoke 会写入可复用偏好'
    },
    [pscustomobject]@{
      kind            = 'correction'
      scenario        = '执行全局沉淀 smoke 时'
      correctApproach = '优先验证路由和索引刷新'
      avoidance       = '不要只验证文件存在'
    },
    [pscustomobject]@{
      kind    = 'globalFact'
      summary = '全局 skill registry 是长期治理入口'
    },
    [pscustomobject]@{
      kind       = 'globalFact'
      summary    = '未验证：这条事实不应被写入'
      notes      = '猜测'
    },
    [pscustomobject]@{
      kind         = 'skillSignal'
      name         = 'distillation-smoke-skill'
      purpose      = '用于验证全局沉淀 helper 会刷新 registry 和索引'
      triggers     = @('smoke', 'distillation')
      scope        = 'global'
      stability    = 'stable'
      relatedDocs  = @('memory-governance.md')
      relatedMemory = @('memory\global\memory-index.md')
    }
  )

  Invoke-GlobalMemoryDistillation -CopilotHome $tempCopilotHome -Candidates $candidates | Out-Null

  $tempProfile = Get-Content -Path (Join-Path $tempCopilotHome 'memory\global\profile.md') -Raw -Encoding UTF8
  if ($tempProfile -notmatch '全局沉淀 smoke 会写入可复用偏好') {
    throw 'Expected helper to append stable preference summary'
  }

  $tempPreferences = Get-Content -Path (Join-Path $tempCopilotHome 'memory\global\preferences.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  if ($tempPreferences.distillationSmokeMode -ne 'enabled') {
    throw 'Expected helper to update preferences.json'
  }

  $tempCorrections = Get-Content -Path (Join-Path $tempCopilotHome 'memory\global\corrections.md') -Raw -Encoding UTF8
  if ($tempCorrections -notmatch '执行全局沉淀 smoke 时') {
    throw 'Expected helper to append correction block'
  }

  $tempFacts = Get-Content -Path (Join-Path $tempCopilotHome 'memory\global\global-facts.md') -Raw -Encoding UTF8
  if ($tempFacts -notmatch '全局 skill registry 是长期治理入口') {
    throw 'Expected helper to append global fact'
  }
  if ($tempFacts -match '未验证：这条事实不应被写入') {
    throw 'Expected helper to skip forbidden global fact signal'
  }

  $tempRegistry = Get-Content -Path (Join-Path $tempCopilotHome 'skills\skill-registry.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  if ('distillation-smoke-skill' -notin @($tempRegistry.skills | ForEach-Object { $_.name })) {
    throw 'Expected helper to append skill signal to registry'
  }

  $tempIndex = Get-Content -Path (Join-Path $tempCopilotHome 'memory\global\memory-index.md') -Raw -Encoding UTF8
  if ($tempIndex -notmatch 'distillation-smoke-skill') {
    throw 'Expected helper to refresh memory index from registry'
  }

  Invoke-GlobalMemoryDistillation -CopilotHome $tempCopilotHome -Candidates @(
    [pscustomobject]@{
      kind    = 'stablePreference'
      key     = 'prefA'
      value   = 'enabled'
      summary = 'prefA enabled summary'
    },
    [pscustomobject]@{
      kind    = 'stablePreference'
      key     = 'prefB'
      value   = 'enabled'
      summary = 'prefB also says enabled'
    }
  ) | Out-Null

  Invoke-GlobalMemoryDistillation -CopilotHome $tempCopilotHome -Candidates @(
    [pscustomobject]@{
      kind    = 'stablePreference'
      key     = 'prefA'
      value   = 'disabled'
      summary = 'prefA disabled summary'
    }
  ) | Out-Null

  $updatedProfile = Get-Content -Path (Join-Path $tempCopilotHome 'memory\global\profile.md') -Raw -Encoding UTF8
  if ($updatedProfile -notmatch 'prefA disabled summary') {
    throw 'Expected stablePreference update to write the new managed summary'
  }
  if ($updatedProfile -match 'prefA enabled summary') {
    throw 'Expected stablePreference update to replace the previous managed summary'
  }
  if ($updatedProfile -notmatch 'prefB also says enabled') {
    throw 'Expected stablePreference update to preserve other preference summaries'
  }
}
finally {
  if (Test-Path $tempRoot) {
    Remove-Item $tempRoot -Recurse -Force
  }
}

$docChecks = [ordered]@{
  InstructionsHasIndexRule   = [bool](Select-String -Path (Join-Path $copilotHome 'copilot-instructions.md') -Pattern 'memory-index.md')
  GovernanceHasRegistry      = [bool](Select-String -Path (Join-Path $copilotHome 'memory-governance.md') -Pattern 'skill-registry.json')
  LifecycleHasGlobalFact     = [bool](Select-String -Path (Join-Path $copilotHome 'memory-lifecycle.md') -Pattern 'global-facts.md')
  HandoffHasIndexRefresh     = [bool](Select-String -Path (Join-Path $copilotHome 'skills\memory-handoff\SKILL.md') -Pattern 'memory-index')
  PreferenceHasIndexRefresh  = [bool](Select-String -Path (Join-Path $copilotHome 'skills\preference-learning\SKILL.md') -Pattern 'memory-index')
  ReadmeHasSmokeCommand      = [bool](Select-String -Path (Join-Path $copilotHome 'README.md') -Pattern 'check-global-memory-distillation-smoke.ps1')
}

foreach ($entry in $docChecks.GetEnumerator()) {
  if (-not $entry.Value) {
    throw "Missing documentation update: $($entry.Key)"
  }
}

Write-Host 'global-memory-distillation smoke PASS'



