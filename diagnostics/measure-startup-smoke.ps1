$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot 'measure-startup.ps1'
$metricsPath = Join-Path $env:TEMP 'measure-startup-metrics-smoke.jsonl'
$hookMetricsPath = Join-Path $env:TEMP 'measure-startup-hook-metrics-smoke.jsonl'
$hookStartProbePath = Join-Path $env:TEMP 'measure-startup-hook-start-smoke.ps1'
$hookEndProbePath = Join-Path $env:TEMP 'measure-startup-hook-end-smoke.ps1'
$missingHookPath = Join-Path $env:TEMP 'measure-startup-missing-hook-smoke.ps1'

if (-not (Test-Path $scriptPath)) {
  throw "Missing script: $scriptPath"
}

try {
  $env:COPILOT_ECC_MEMORY_METRICS_PATH = $hookMetricsPath
  $env:COPILOT_ECC_MEMORY_METRICS_KEEP_LAST = '10'

  @'
param()
Write-Output '{"continue":true}'
'@ | Set-Content -Path $hookStartProbePath -Encoding UTF8

  @'
param()
Start-Sleep -Milliseconds 500
Write-Output '{"continue":true}'
'@ | Set-Content -Path $hookEndProbePath -Encoding UTF8

  $resultWithDefaultHooks = & $scriptPath -Runs 1 -MetricsPath $metricsPath | ConvertFrom-Json
  if ($null -eq $resultWithDefaultHooks.phases.resolveProjectMs) {
    throw 'Missing phases.resolveProjectMs'
  }

  if ($null -eq $resultWithDefaultHooks.phases.writeMetadataMs) {
    throw 'Missing phases.writeMetadataMs'
  }

  $result = & $scriptPath -Runs 1 -HookStartPath $hookStartProbePath -HookEndPath $hookEndProbePath -MetricsPath $metricsPath | ConvertFrom-Json

  if ($null -eq $result.totalMs) {
    throw 'Missing totalMs'
  }

  if ($null -eq $result.phases.hookStartMs) {
    throw 'Missing phases.hookStartMs'
  }

  if ($null -eq $result.phases.hookEndMs) {
    throw 'Missing phases.hookEndMs'
  }

  if (-not $result.loginState.PSObject.Properties['hasCachedLogin']) {
    throw 'Missing loginState.hasCachedLogin'
  }

  if (-not $result.loginState.PSObject.Properties['lastLogin']) {
    throw 'Missing loginState.lastLogin'
  }

  if ($result.loginState.loginCheckTriggered -ne $true) {
    throw 'Missing or false loginState.loginCheckTriggered'
  }

  if (-not $result.projectContext.PSObject.Properties['projectMemoryRestoreTriggered']) {
    throw 'Missing projectContext.projectMemoryRestoreTriggered'
  }

  if (-not $result.projectContext.PSObject.Properties['projectKey']) {
    throw 'Missing projectContext.projectKey'
  }

  if (-not $result.projectContext.PSObject.Properties['projectRoot']) {
    throw 'Missing projectContext.projectRoot'
  }

  if ($result.projectContext.projectMemoryRestoreTriggered -ne $false) {
    throw "Expected projectMemoryRestoreTriggered to stay false, got $($result.projectContext.projectMemoryRestoreTriggered)"
  }

  if ($result.phases.hookEndMs -lt 400) {
    throw "Expected delayed hookEndMs, got $($result.phases.hookEndMs)"
  }

  if ($result.totalMs -ge 400) {
    throw "totalMs should exclude delayed hookEndMs, got $($result.totalMs)"
  }

  if (-not (Test-Path $metricsPath)) {
    throw "Missing metrics log: $metricsPath"
  }

  $metricsLines = @(Get-Content -Path $metricsPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  if ($metricsLines.Count -lt 1) {
    throw 'Metrics log is empty'
  }

  $logEntry = $metricsLines[-1] | ConvertFrom-Json
  if ($logEntry.totalMs -ne $result.totalMs) {
    throw 'Metrics log last entry does not match command output'
  }

  $resultWithoutHookEnd = & $scriptPath -Runs 1 -HookStartPath $hookStartProbePath -HookEndPath $missingHookPath -MetricsPath $metricsPath | ConvertFrom-Json
  if ($resultWithoutHookEnd.phases.hookEndMs -ne 0) {
    throw "Expected hookEndMs to be 0 with missing HookEndPath override, got $($resultWithoutHookEnd.phases.hookEndMs)"
  }

  $resultWithoutHooks = & $scriptPath -Runs 1 -HookStartPath $missingHookPath -HookEndPath $missingHookPath -MetricsPath $metricsPath | ConvertFrom-Json
  if ($resultWithoutHooks.phases.hookStartMs -ne 0) {
    throw "Expected hookStartMs to be 0 with missing HookStartPath override, got $($resultWithoutHooks.phases.hookStartMs)"
  }

  if ($resultWithoutHooks.phases.hookEndMs -ne 0) {
    throw "Expected hookEndMs to be 0 with missing HookEndPath override, got $($resultWithoutHooks.phases.hookEndMs)"
  }
}
finally {
  Remove-Item Env:\COPILOT_ECC_MEMORY_METRICS_PATH -ErrorAction SilentlyContinue
  Remove-Item Env:\COPILOT_ECC_MEMORY_METRICS_KEEP_LAST -ErrorAction SilentlyContinue

  if (Test-Path $metricsPath) {
    Remove-Item $metricsPath -Force
  }

  if (Test-Path $hookMetricsPath) {
    Remove-Item $hookMetricsPath -Force
  }

  if (Test-Path $hookStartProbePath) {
    Remove-Item $hookStartProbePath -Force
  }

  if (Test-Path $hookEndProbePath) {
    Remove-Item $hookEndProbePath -Force
  }
}

Write-Host 'measure-startup smoke PASS'
