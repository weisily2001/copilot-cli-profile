param()

$ErrorActionPreference = 'Stop'
$copilotHome = Split-Path -Parent $PSScriptRoot
$shared = Join-Path $copilotHome 'hooks\ecc-memory\shared.ps1'
$sessionStart = Join-Path $copilotHome 'hooks\ecc-memory\session-start.ps1'
$sessionEnd = Join-Path $copilotHome 'hooks\ecc-memory\session-end.ps1'

if (-not (Test-Path $shared)) { throw "Missing shared helper: $shared" }
if (-not (Test-Path $sessionStart)) { throw "Missing session-start hook: $sessionStart" }
if (-not (Test-Path $sessionEnd)) { throw "Missing session-end hook: $sessionEnd" }

$tempRoot = Join-Path $env:TEMP 'hook-metrics-smoke'
$projectsRoot = Join-Path $tempRoot 'projects'
$projectDir = Join-Path $projectsRoot 'hook-metrics-smoke'
$fixtureRoot = Join-Path $tempRoot 'fixture-root'
$metricsPath = Join-Path $tempRoot 'startup-metrics.jsonl'
$cachePath = Join-Path $tempRoot 'project-context-cache.json'
$probeCopilotHome = Join-Path $tempRoot 'probe-home\.copilot'
$probeProjectsRoot = Join-Path $tempRoot 'probe-projects'
$probeProjectDir = Join-Path $probeProjectsRoot 'hook-metrics-probe'
$probeFixtureRoot = Join-Path $tempRoot 'probe-fixture-root'
$probeMetricsPath = Join-Path $tempRoot 'probe-metrics.jsonl'
$probeCachePath = Join-Path $tempRoot 'probe-project-context-cache.json'
$probeFailureMetricsPath = Join-Path $tempRoot 'probe-failure-metrics.jsonl'
$probeFactSummary = 'hook-metrics smoke integrated session-end distillation'
$brokenCacheDir = Join-Path $tempRoot 'missing-cache-dir'
$bootstrapMetricsPath = Join-Path $tempRoot 'bootstrap-metrics.jsonl'
$brokenSessionStart = Join-Path $tempRoot 'broken-session-start.ps1'

try {
  New-Item -ItemType Directory -Force -Path $projectDir, $fixtureRoot | Out-Null
  $env:COPILOT_ECC_MEMORY_PROJECTS_ROOT = $projectsRoot
  $env:COPILOT_ECC_MEMORY_CACHE_PATH = $cachePath
  $env:COPILOT_ECC_MEMORY_METRICS_PATH = $metricsPath
  $env:COPILOT_ECC_MEMORY_METRICS_KEEP_LAST = '2'

  . $shared

  @'
{
  "projectKey": "hook-metrics-smoke",
  "projectRoot": "__ROOT__"
}
'@.Replace('__ROOT__', $fixtureRoot.Replace('\', '\\')) | Set-Content -Path (Join-Path $projectDir 'project.json') -Encoding UTF8

  Push-Location $fixtureRoot
  try {
    & $sessionStart
    & $sessionEnd
  }
  finally {
    Pop-Location
  }

  if (-not (Test-Path $metricsPath)) {
    throw "Expected metrics log at '$metricsPath'"
  }

  $lines = @(Get-Content -Path $metricsPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  if ($lines.Count -ne 2) {
    throw "Expected 2 metric lines, got $($lines.Count)"
  }

  $records = $lines | ForEach-Object { $_ | ConvertFrom-Json }
  $events = $records.event
  if (@($events) -notcontains 'sessionStart' -or @($events) -notcontains 'sessionEnd') {
    throw "Expected sessionStart/sessionEnd events, got '$($events -join ',')'"
  }

  foreach ($record in $records) {
    foreach ($field in 'resolveProjectMs', 'writeMetadataMs', 'event', 'projectKey', 'projectRoot', 'timestamp') {
      if ($null -eq $record.$field -or [string]::IsNullOrWhiteSpace([string]$record.$field)) {
        throw "Missing field '$field' in metric record"
      }
    }
  }

  $lastSessionPath = Join-Path $projectDir 'last-session.json'
  if (-not (Test-Path $lastSessionPath)) {
    throw "Expected last-session metadata at '$lastSessionPath'"
  }

  New-Item -ItemType Directory -Force -Path (Join-Path $probeCopilotHome 'hooks\ecc-memory'), (Join-Path $probeCopilotHome 'memory\global'), (Join-Path $probeCopilotHome 'skills'), $probeProjectDir, $probeFixtureRoot | Out-Null
  Copy-Item -Path $shared -Destination (Join-Path $probeCopilotHome 'hooks\ecc-memory\shared.ps1') -Force
  Copy-Item -Path $sessionStart -Destination (Join-Path $probeCopilotHome 'hooks\ecc-memory\session-start.ps1') -Force
  Copy-Item -Path $sessionEnd -Destination (Join-Path $probeCopilotHome 'hooks\ecc-memory\session-end.ps1') -Force
  Copy-Item -Path (Join-Path $copilotHome 'hooks\ecc-memory\global-distillation.ps1') -Destination (Join-Path $probeCopilotHome 'hooks\ecc-memory\global-distillation.ps1') -Force
  Copy-Item -Path (Join-Path $copilotHome 'memory\global\memory-index.md') -Destination (Join-Path $probeCopilotHome 'memory\global\memory-index.md') -Force
  Copy-Item -Path (Join-Path $copilotHome 'memory\global\global-facts.md') -Destination (Join-Path $probeCopilotHome 'memory\global\global-facts.md') -Force
  Copy-Item -Path (Join-Path $copilotHome 'memory\global\distillation-rules.json') -Destination (Join-Path $probeCopilotHome 'memory\global\distillation-rules.json') -Force
  Copy-Item -Path (Join-Path $copilotHome 'memory\global\profile.md') -Destination (Join-Path $probeCopilotHome 'memory\global\profile.md') -Force
  Copy-Item -Path (Join-Path $copilotHome 'memory\global\preferences.json') -Destination (Join-Path $probeCopilotHome 'memory\global\preferences.json') -Force
  Copy-Item -Path (Join-Path $copilotHome 'memory\global\corrections.md') -Destination (Join-Path $probeCopilotHome 'memory\global\corrections.md') -Force
  Copy-Item -Path (Join-Path $copilotHome 'skills\skill-registry.json') -Destination (Join-Path $probeCopilotHome 'skills\skill-registry.json') -Force

  @'
{
  "projectKey": "hook-metrics-probe",
  "projectRoot": "__ROOT__"
}
'@.Replace('__ROOT__', $probeFixtureRoot.Replace('\', '\\')) | Set-Content -Path (Join-Path $probeProjectDir 'project.json') -Encoding UTF8

  $probeSessionEnd = Join-Path $probeCopilotHome 'hooks\ecc-memory\session-end.ps1'
  $probeInvocation = "Invoke-GlobalMemoryDistillation -CopilotHome (Get-HookCopilotHome) -ForceIndexSync | Out-Null"
  $probeReplacement = "Invoke-GlobalMemoryDistillation -CopilotHome (Get-HookCopilotHome) -Candidates @([pscustomobject]@{ kind = 'globalFact'; summary = '$probeFactSummary' }) -ForceIndexSync | Out-Null"
  (Get-Content -Path $probeSessionEnd -Raw -Encoding UTF8).Replace($probeInvocation, $probeReplacement) | Set-Content -Path $probeSessionEnd -Encoding UTF8

  $env:COPILOT_ECC_MEMORY_PROJECTS_ROOT = $probeProjectsRoot
  $env:COPILOT_ECC_MEMORY_CACHE_PATH = $probeCachePath
  $env:COPILOT_ECC_MEMORY_METRICS_PATH = $probeMetricsPath

  Push-Location $probeFixtureRoot
  try {
    & $probeSessionEnd
  }
  finally {
    Pop-Location
  }

  $probeFactsPath = Join-Path $probeCopilotHome 'memory\global\global-facts.md'
  $probeFacts = Get-Content -Path $probeFactsPath -Raw -Encoding UTF8
  if ($probeFacts -notmatch [regex]::Escape($probeFactSummary)) {
    throw 'Expected session-end probe to invoke global distillation helper'
  }

  Set-Content -Path (Join-Path $probeCopilotHome 'hooks\ecc-memory\global-distillation.ps1') -Value "throw 'probe distillation failure'" -Encoding UTF8
  $env:COPILOT_ECC_MEMORY_METRICS_PATH = $probeFailureMetricsPath

  Push-Location $probeFixtureRoot
  try {
    $probeFailureOutput = & $probeSessionEnd 2>&1
  }
  finally {
    Pop-Location
  }

  if (-not ($probeFailureOutput -match '\{"continue":true\}')) {
    throw 'Expected distillation failure probe to still emit continue output'
  }

  $probeFailureLines = @(Get-Content -Path $probeFailureMetricsPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  if ($probeFailureLines.Count -lt 1) {
    throw 'Expected distillation failure probe to write metrics'
  }

  $probeFailureRecord = $probeFailureLines[-1] | ConvertFrom-Json
  if ($probeFailureRecord.status -ne 'successWithDistillationWarning') {
    throw "Expected distillation failure probe status successWithDistillationWarning, got '$($probeFailureRecord.status)'"
  }

  if ([string]::IsNullOrWhiteSpace([string]$probeFailureRecord.error)) {
    throw 'Expected distillation failure probe to record error details'
  }

  $env:COPILOT_ECC_MEMORY_PROJECTS_ROOT = $projectsRoot
  $env:COPILOT_ECC_MEMORY_CACHE_PATH = $cachePath
  $env:COPILOT_ECC_MEMORY_METRICS_PATH = $metricsPath

  Push-Location $tempRoot
  try {
    & $sessionStart
  }
  finally {
    Pop-Location
  }

  $env:COPILOT_ECC_MEMORY_CACHE_PATH = Join-Path $brokenCacheDir 'project-context-cache.json'

  Push-Location $fixtureRoot
  try {
    & $sessionStart
  }
  finally {
    Pop-Location
  }

  $finalLines = @(Get-Content -Path $metricsPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  if ($finalLines.Count -ne 2) {
    throw "Expected retention to keep 2 metric lines, got $($finalLines.Count)"
  }

  $finalRecords = $finalLines | ForEach-Object { $_ | ConvertFrom-Json }
  if ($finalRecords[0].status -ne 'unresolved') {
    throw "Expected first retained record to be unresolved, got '$($finalRecords[0].status)'"
  }

  if ($finalRecords[0].event -ne 'sessionStart') {
    throw "Expected unresolved event to be sessionStart, got '$($finalRecords[0].event)'"
  }

  if ([string]::IsNullOrWhiteSpace([string]$finalRecords[0].error)) {
    throw 'Expected unresolved record to contain error'
  }

  if ($finalRecords[1].status -ne 'metadataWriteFailed') {
    throw "Expected second retained record to be metadataWriteFailed, got '$($finalRecords[1].status)'"
  }

  if ($finalRecords[1].writeMetadataMs -ne 0) {
    throw "Expected failed metadata write to keep writeMetadataMs at 0, got $($finalRecords[1].writeMetadataMs)"
  }

  if ([string]::IsNullOrWhiteSpace([string]$finalRecords[1].error)) {
    throw 'Expected metadataWriteFailed record to contain error'
  }

  $brokenSharedPath = Join-Path $tempRoot 'missing-shared.ps1'
  (Get-Content -Path $sessionStart -Raw -Encoding UTF8).Replace("Join-Path `$PSScriptRoot 'shared.ps1'", "'$brokenSharedPath'") | Set-Content -Path $brokenSessionStart -Encoding UTF8
  $env:COPILOT_ECC_MEMORY_METRICS_PATH = $bootstrapMetricsPath

  Push-Location $fixtureRoot
  try {
    $bootstrapOutput = & $brokenSessionStart 2>&1
  }
  finally {
    Pop-Location
  }

  if (-not ($bootstrapOutput -match '\{"continue":true\}')) {
    throw 'Expected bootstrap failure script to still emit continue output'
  }

  if (-not (Test-Path $bootstrapMetricsPath)) {
    throw "Expected bootstrap metrics log at '$bootstrapMetricsPath'"
  }

  $bootstrapLines = @(Get-Content -Path $bootstrapMetricsPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  if ($bootstrapLines.Count -lt 1) {
    throw 'Expected bootstrap metrics log to contain at least one record'
  }

  $bootstrapRecord = $bootstrapLines[-1] | ConvertFrom-Json
  if ($bootstrapRecord.status -ne 'hookFailed') {
    throw "Expected bootstrap failure status hookFailed, got '$($bootstrapRecord.status)'"
  }
}
finally {
  if (Test-Path $tempRoot) {
    Remove-Item $tempRoot -Recurse -Force
  }
  Remove-Item Env:\COPILOT_ECC_MEMORY_PROJECTS_ROOT -ErrorAction SilentlyContinue
  Remove-Item Env:\COPILOT_ECC_MEMORY_CACHE_PATH -ErrorAction SilentlyContinue
  Remove-Item Env:\COPILOT_ECC_MEMORY_METRICS_PATH -ErrorAction SilentlyContinue
  Remove-Item Env:\COPILOT_ECC_MEMORY_METRICS_KEEP_LAST -ErrorAction SilentlyContinue
}

Write-Host 'hook-metrics smoke PASS'
