param(
  [int]$Runs = 1,
  [string]$HookStartPath,
  [string]$HookEndPath,
  [string]$MetricsPath
)

$ErrorActionPreference = 'Stop'
$copilotHome = Join-Path $HOME '.copilot'
$metricsPath = if ($MetricsPath) { $MetricsPath } else { Join-Path $copilotHome 'startup-metrics.jsonl' }
$hookMetricsPath = if (-not [string]::IsNullOrWhiteSpace($env:COPILOT_ECC_MEMORY_METRICS_PATH)) { $env:COPILOT_ECC_MEMORY_METRICS_PATH } else { Join-Path $copilotHome 'hook-metrics.jsonl' }
$configPath = Join-Path $copilotHome 'config.json'
$hookStart = if ([string]::IsNullOrWhiteSpace($HookStartPath)) { Join-Path $copilotHome 'hooks\ecc-memory\session-start.ps1' } else { $HookStartPath }
$hookEnd = if ([string]::IsNullOrWhiteSpace($HookEndPath)) { Join-Path $copilotHome 'hooks\ecc-memory\session-end.ps1' } else { $HookEndPath }
$projectsRoot = Join-Path $copilotHome 'memory\projects'
$currentPath = (Get-Location).Path

function Get-LoginState {
  param([string]$Path)

  if (-not (Test-Path $Path)) {
    return [ordered]@{
      hasCachedLogin = $false
      lastLogin      = $null
    }
  }

  $raw = Get-Content -Path $Path -Raw
  $json = ($raw -split "\r?\n" | Where-Object { $_ -notmatch '^\s*//' }) -join [Environment]::NewLine
  $config = $json | ConvertFrom-Json
  $user = $config.lastLoggedInUser

  return [ordered]@{
    hasCachedLogin = $null -ne $user
    lastLogin      = if ($null -ne $user) { [string]$user.login } else { $null }
  }
}

function Get-NormalizedProjectKey {
  param([string]$Path)

  $leaf = Split-Path $Path -Leaf
  if ([string]::IsNullOrWhiteSpace($leaf)) {
    return $null
  }

  return $leaf.ToLowerInvariant()
}

function Get-RecordedProjectRoot {
  param([string]$ProjectDir)

  $projectJsonPath = Join-Path $ProjectDir 'project.json'
  if (Test-Path $projectJsonPath) {
    try {
      $projectMeta = Get-Content -Path $projectJsonPath -Raw | ConvertFrom-Json
      $projectRoot = [string]$projectMeta.projectRoot
      if (-not [string]::IsNullOrWhiteSpace($projectRoot)) {
        return $projectRoot.Trim()
      }
    }
    catch {
      [Console]::Error.WriteLine("Warning: failed to read '$projectJsonPath': $($_.Exception.Message)")
    }
  }

  return $null
}

function Get-RecordedProjectKey {
  param([string]$ProjectDir)

  $projectJsonPath = Join-Path $ProjectDir 'project.json'
  if (Test-Path $projectJsonPath) {
    try {
      $projectMeta = Get-Content -Path $projectJsonPath -Raw | ConvertFrom-Json
      $projectKey = [string]$projectMeta.projectKey
      if (-not [string]::IsNullOrWhiteSpace($projectKey)) {
        return $projectKey.Trim().ToLowerInvariant()
      }
    }
    catch {
      [Console]::Error.WriteLine("Warning: failed to read '$projectJsonPath': $($_.Exception.Message)")
    }
  }

  return (Split-Path $ProjectDir -Leaf).ToLowerInvariant()
}

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

function Resolve-ProjectContext {
  param(
    [string]$Path,
    [string]$ProjectsRoot
  )

  if (-not (Test-Path $ProjectsRoot)) {
    return $null
  }

  $leafKey = Get-NormalizedProjectKey -Path $Path
  if ($leafKey) {
    $leafProjectDir = Join-Path $ProjectsRoot $leafKey
    if (Test-Path $leafProjectDir) {
      $recordedRoot = Get-RecordedProjectRoot -ProjectDir $leafProjectDir
      if ($recordedRoot -and (Test-IsSameOrChildPath -Path $Path -CandidateRoot $recordedRoot)) {
        return [pscustomobject]@{
          ProjectKey  = Get-RecordedProjectKey -ProjectDir $leafProjectDir
          ProjectRoot = [System.IO.Path]::GetFullPath($recordedRoot).TrimEnd('\')
        }
      }
    }
  }

  $bestMatch = $null
  foreach ($projectDir in Get-ChildItem -Path $ProjectsRoot -Directory) {
    $recordedRoot = Get-RecordedProjectRoot -ProjectDir $projectDir.FullName
    if (-not $recordedRoot) {
      continue
    }

    if (-not (Test-IsSameOrChildPath -Path $Path -CandidateRoot $recordedRoot)) {
      continue
    }

    $normalizedRoot = [System.IO.Path]::GetFullPath($recordedRoot).TrimEnd('\')
    if (($null -eq $bestMatch) -or ($normalizedRoot.Length -gt $bestMatch.ProjectRoot.Length)) {
      $bestMatch = [pscustomobject]@{
        ProjectKey  = Get-RecordedProjectKey -ProjectDir $projectDir.FullName
        ProjectRoot = $normalizedRoot
      }
    }
  }

  return $bestMatch
}

function Measure-Phase {
  param(
    [scriptblock]$Action
  )

  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  & $Action | Out-Null
  $sw.Stop()
  $sw.ElapsedMilliseconds
}

function Measure-Value {
  param(
    [scriptblock]$Action
  )

  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $value = & $Action
  $sw.Stop()

  [pscustomobject]@{
    Value = $value
    Ms    = $sw.ElapsedMilliseconds
  }
}

function Trim-MetricsLog {
  param(
    [string]$Path,
    [int]$KeepLast = 100
  )

  if (-not (Test-Path $Path)) {
    return
  }

  $lines = Get-Content -Path $Path
  if ($lines.Count -le $KeepLast) {
    return
  }

  $lines | Select-Object -Last $KeepLast | Set-Content -Path $Path -Encoding UTF8
}

function Get-MetricsLineCount {
  param([string]$Path)

  if (-not (Test-Path $Path)) {
    return 0
  }

  return @(
    Get-Content -Path $Path |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  ).Count
}

function Get-LatestHookMetric {
  param(
    [string]$Path,
    [int]$StartIndex = 0
  )

  if (-not (Test-Path $Path)) {
    return $null
  }

  $lines = @(
    Get-Content -Path $Path |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  )
  if ($StartIndex -lt 0) {
    $StartIndex = 0
  }

  for ($index = $lines.Count - 1; $index -ge $StartIndex; $index--) {
    try {
      $record = $lines[$index] | ConvertFrom-Json
      if ($record.PSObject.Properties['resolveProjectMs'] -or $record.PSObject.Properties['writeMetadataMs']) {
        return $record
      }
    }
    catch {
    }
  }

  return $null
}

$runsOutput = @()

for ($i = 0; $i -lt $Runs; $i++) {
  $total = [System.Diagnostics.Stopwatch]::StartNew()
  $hookMetricsLineCountBefore = Get-MetricsLineCount -Path $hookMetricsPath

  $loginStateMetric = Measure-Value -Action {
    Get-LoginState -Path $configPath
  }
  $projectContextMetric = Measure-Value -Action {
    Resolve-ProjectContext -Path $currentPath -ProjectsRoot $projectsRoot
  }
  $hookStartMs = Measure-Phase -Action {
    if (Test-Path $hookStart) {
      & $hookStart
    }
  }

  $total.Stop()

  $hookEndMs = Measure-Phase -Action {
    if ($hookEnd -and (Test-Path $hookEnd)) {
      & $hookEnd
    }
  }

  $projectContext = $projectContextMetric.Value
  $latestHookMetric = Get-LatestHookMetric -Path $hookMetricsPath -StartIndex $hookMetricsLineCountBefore
  $loginState = [ordered]@{
    hasCachedLogin      = $loginStateMetric.Value.hasCachedLogin
    lastLogin           = $loginStateMetric.Value.lastLogin
    loginCheckTriggered = $true
  }
  $projectOutput = [ordered]@{
    projectKey                    = $null
    projectRoot                   = $null
    projectMemoryRestoreTriggered = $false
  }

  if ($null -ne $projectContext) {
    $projectOutput.projectKey = $projectContext.ProjectKey
    $projectOutput.projectRoot = $projectContext.ProjectRoot
  }

  $run = [ordered]@{
    timestamp      = (Get-Date).ToString('o')
    totalMs        = [int64]$total.ElapsedMilliseconds
    phases         = [ordered]@{
      loginStateMs      = [int64]$loginStateMetric.Ms
      projectContextMs  = [int64]$projectContextMetric.Ms
      hookStartMs       = [int64]$hookStartMs
      hookEndMs         = [int64]$hookEndMs
      resolveProjectMs  = if ($null -ne $latestHookMetric -and $null -ne $latestHookMetric.resolveProjectMs) { [int64]$latestHookMetric.resolveProjectMs } else { [int64]0 }
      writeMetadataMs   = if ($null -ne $latestHookMetric -and $null -ne $latestHookMetric.writeMetadataMs) { [int64]$latestHookMetric.writeMetadataMs } else { [int64]0 }
    }
    loginState     = $loginState
    projectContext = $projectOutput
  }

  $runsOutput += $run
  ($run | ConvertTo-Json -Depth 5 -Compress) | Add-Content -Path $metricsPath -Encoding UTF8
  Trim-MetricsLog -Path $metricsPath
}

$runsOutput[-1] | ConvertTo-Json -Depth 5
