$ErrorActionPreference = 'Stop'

$script:CopilotHome = Join-Path $HOME '.copilot'
$script:ProjectsRootDefault = if (-not [string]::IsNullOrWhiteSpace($env:COPILOT_ECC_MEMORY_PROJECTS_ROOT)) { $env:COPILOT_ECC_MEMORY_PROJECTS_ROOT } else { Join-Path $script:CopilotHome 'memory\projects' }
$script:ProjectContextCachePath = if (-not [string]::IsNullOrWhiteSpace($env:COPILOT_ECC_MEMORY_CACHE_PATH)) { $env:COPILOT_ECC_MEMORY_CACHE_PATH } else { Join-Path $script:CopilotHome 'memory\project-context-cache.json' }
$script:EccMetricsPath = Join-Path $script:CopilotHome 'hook-metrics.jsonl'
$script:EccMetricsKeepLastDefault = 100

function Get-NormalizedProjectKey {
  param([string]$Path)

  $leaf = Split-Path $Path -Leaf
  if ([string]::IsNullOrWhiteSpace($leaf)) {
    return $null
  }

  return $leaf.Trim().ToLowerInvariant()
}

function Get-ProjectJsonContext {
  param([string]$ProjectDir)

  $projectJsonPath = Join-Path $ProjectDir 'project.json'
  if (-not (Test-Path $projectJsonPath)) {
    return $null
  }

  try {
    $projectMeta = Get-Content -Path $projectJsonPath -Raw | ConvertFrom-Json
    $projectRoot = [string]$projectMeta.projectRoot
    if ([string]::IsNullOrWhiteSpace($projectRoot)) {
      return $null
    }

    $projectKey = [string]$projectMeta.projectKey
    if ([string]::IsNullOrWhiteSpace($projectKey)) {
      $projectKey = Split-Path $ProjectDir -Leaf
    }

    return [pscustomobject]@{
      ProjectKey  = $projectKey.Trim().ToLowerInvariant()
      ProjectRoot = $projectRoot.Trim()
      ProjectDir  = $ProjectDir
    }
  }
  catch {
    [Console]::Error.WriteLine("Warning: failed to read '$projectJsonPath': $($_.Exception.Message)")
    return $null
  }
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

function Get-ProjectContextCache {
  if (-not (Test-Path $script:ProjectContextCachePath)) {
    return $null
  }

  try {
    $cache = Get-Content -Path $script:ProjectContextCachePath -Raw | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace([string]$cache.projectRoot)) {
      return $null
    }

    $projectKey = [string]$cache.projectKey
    if ([string]::IsNullOrWhiteSpace($projectKey)) {
      $projectKey = Split-Path ([string]$cache.projectRoot) -Leaf
    }

    return [pscustomobject]@{
      ProjectKey  = $projectKey.Trim().ToLowerInvariant()
      ProjectRoot = ([string]$cache.projectRoot).Trim()
      ProjectDir  = if ([string]::IsNullOrWhiteSpace([string]$cache.projectDir)) { $null } else { ([string]$cache.projectDir).Trim() }
    }
  }
  catch {
    return $null
  }
}

function Select-PreferredProjectContext {
  param(
    $Current,
    $Candidate
  )

  if ($null -eq $Candidate) {
    return $Current
  }

  if ($null -eq $Current) {
    return [pscustomobject]@{
      ProjectKey  = $Candidate.ProjectKey
      ProjectRoot = [System.IO.Path]::GetFullPath($Candidate.ProjectRoot).TrimEnd('\')
      ProjectDir  = if ([string]::IsNullOrWhiteSpace([string]$Candidate.ProjectDir)) { $null } else { $Candidate.ProjectDir }
    }
  }

  $currentRoot = [System.IO.Path]::GetFullPath($Current.ProjectRoot).TrimEnd('\')
  $candidateRoot = [System.IO.Path]::GetFullPath($Candidate.ProjectRoot).TrimEnd('\')
  if ($candidateRoot.Length -gt $currentRoot.Length) {
    return [pscustomobject]@{
      ProjectKey  = $Candidate.ProjectKey
      ProjectRoot = $candidateRoot
      ProjectDir  = if ([string]::IsNullOrWhiteSpace([string]$Candidate.ProjectDir)) { $null } else { $Candidate.ProjectDir }
    }
  }

  if ($candidateRoot.Equals($currentRoot, [System.StringComparison]::OrdinalIgnoreCase) -and -not [string]::IsNullOrWhiteSpace([string]$Candidate.ProjectDir)) {
    return [pscustomobject]@{
      ProjectKey  = $Candidate.ProjectKey
      ProjectRoot = $candidateRoot
      ProjectDir  = $Candidate.ProjectDir
    }
  }

  return [pscustomobject]@{
    ProjectKey  = $Current.ProjectKey
    ProjectRoot = $currentRoot
    ProjectDir  = if ([string]::IsNullOrWhiteSpace([string]$Current.ProjectDir)) { $null } else { $Current.ProjectDir }
  }
}

function Resolve-ProjectContextFast {
  param(
    [string]$Path,
    [string]$ProjectsRoot = $script:ProjectsRootDefault
  )

  if (-not (Test-Path $ProjectsRoot)) {
    return $null
  }

  $bestMatch = $null
  $diskMatches = @()
  $cachedContext = Get-ProjectContextCache
  if ($cachedContext -and (Test-IsSameOrChildPath -Path $Path -CandidateRoot $cachedContext.ProjectRoot)) {
    $bestMatch = Select-PreferredProjectContext -Current $bestMatch -Candidate $cachedContext
  }

  $leafKey = Get-NormalizedProjectKey -Path $Path
  if ($leafKey) {
    $leafProjectDir = Join-Path $ProjectsRoot $leafKey
    if (Test-Path $leafProjectDir) {
      $leafContext = Get-ProjectJsonContext -ProjectDir $leafProjectDir
      if ($leafContext -and (Test-IsSameOrChildPath -Path $Path -CandidateRoot $leafContext.ProjectRoot)) {
        $diskMatches += $leafContext
        $bestMatch = Select-PreferredProjectContext -Current $bestMatch -Candidate $leafContext
      }
    }
  }

  foreach ($projectDir in Get-ChildItem -Path $ProjectsRoot -Directory) {
    $projectContext = Get-ProjectJsonContext -ProjectDir $projectDir.FullName
    if (-not $projectContext) {
      continue
    }

    if (-not (Test-IsSameOrChildPath -Path $Path -CandidateRoot $projectContext.ProjectRoot)) {
      continue
    }

    $diskMatches += $projectContext
    $bestMatch = Select-PreferredProjectContext -Current $bestMatch -Candidate $projectContext
  }

  if ($null -ne $bestMatch -and $diskMatches.Count -gt 0) {
    $bestRoot = [System.IO.Path]::GetFullPath($bestMatch.ProjectRoot).TrimEnd('\')
    $conflictingDirs = @(
      $diskMatches |
        Where-Object { [System.IO.Path]::GetFullPath($_.ProjectRoot).TrimEnd('\').Equals($bestRoot, [System.StringComparison]::OrdinalIgnoreCase) } |
        ForEach-Object { [System.IO.Path]::GetFullPath($_.ProjectDir).TrimEnd('\') } |
        Sort-Object -Unique
    )

    if ($conflictingDirs.Count -gt 1) {
      return $null
    }
  }

  return $bestMatch
}

function Write-LastSessionMetadata {
  param(
    [string]$ProjectKey,
    [string]$ProjectRoot,
    [string]$EventName,
    [string]$ProjectDir,
    [string]$ProjectsRoot = $script:ProjectsRootDefault
  )

  $payload = [ordered]@{
    event       = $EventName
    projectRoot = [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
    projectKey  = $ProjectKey.Trim().ToLowerInvariant()
    projectDir  = if ([string]::IsNullOrWhiteSpace($ProjectDir)) { $null } else { [System.IO.Path]::GetFullPath($ProjectDir).TrimEnd('\') }
    timestamp   = Get-Date -Format o
  } | ConvertTo-Json -Compress

  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  $targetProjectDir = if ([string]::IsNullOrWhiteSpace($ProjectDir)) { Join-Path $ProjectsRoot $ProjectKey } else { [System.IO.Path]::GetFullPath($ProjectDir).TrimEnd('\') }
  $projectSessionPath = Join-Path $targetProjectDir 'last-session.json'

  $writeStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
  [System.IO.File]::WriteAllText($projectSessionPath, $payload, $utf8NoBom)
  [System.IO.File]::WriteAllText($script:ProjectContextCachePath, $payload, $utf8NoBom)
  $writeStopwatch.Stop()

  return [int64]$writeStopwatch.ElapsedMilliseconds
}

function Get-EccMetricsPath {
  param([string]$Path)

  if (-not [string]::IsNullOrWhiteSpace($Path)) {
    return $Path
  }

  if (-not [string]::IsNullOrWhiteSpace($env:COPILOT_ECC_MEMORY_METRICS_PATH)) {
    return $env:COPILOT_ECC_MEMORY_METRICS_PATH
  }

  return $script:EccMetricsPath
}

function Get-EccMetricsKeepLast {
  $raw = $env:COPILOT_ECC_MEMORY_METRICS_KEEP_LAST
  if ([string]::IsNullOrWhiteSpace($raw)) {
    return $script:EccMetricsKeepLastDefault
  }

  try {
    $parsed = [int]$raw
    if ($parsed -gt 0) {
      return $parsed
    }
  }
  catch {
  }

  return $script:EccMetricsKeepLastDefault
}

function Write-EccMetricsRecord {
  param(
    [hashtable]$Record,
    [string]$Path,
    [int]$KeepLast = $(Get-EccMetricsKeepLast)
  )

  if ($null -eq $Record) {
    return
  }

  $metricsPath = Get-EccMetricsPath -Path $Path
  $metricsDir = Split-Path $metricsPath -Parent
  if (-not [string]::IsNullOrWhiteSpace($metricsDir)) {
    [System.IO.Directory]::CreateDirectory($metricsDir) | Out-Null
  }

  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  $line = ($Record | ConvertTo-Json -Depth 5 -Compress) + [Environment]::NewLine
  [System.IO.File]::AppendAllText($metricsPath, $line, $utf8NoBom)

  if ($KeepLast -le 0 -or -not (Test-Path $metricsPath)) {
    return
  }

  $lines = Get-Content -Path $metricsPath
  if ($lines.Count -le $KeepLast) {
    return
  }

  $tail = $lines | Select-Object -Last $KeepLast
  [System.IO.File]::WriteAllLines($metricsPath, $tail, $utf8NoBom)
}

function Write-ProjectLifecycleMetrics {
  param(
    [string]$EventName,
    [string]$ProjectKey,
    [string]$ProjectRoot,
    [int64]$ResolveProjectMs,
    [int64]$WriteMetadataMs,
    [string]$ProjectDir,
    [string]$MetricsPath,
    [string]$Status = 'success',
    [string]$ErrorMessage,
    [string]$CurrentPath
  )

  $record = [ordered]@{
    timestamp        = (Get-Date).ToString('o')
    event            = $EventName
    projectKey       = [string]$ProjectKey
    projectRoot      = if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $null } else { [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\') }
    projectDir       = if ([string]::IsNullOrWhiteSpace($ProjectDir)) { $null } else { [System.IO.Path]::GetFullPath($ProjectDir).TrimEnd('\') }
    currentPath      = if ([string]::IsNullOrWhiteSpace($CurrentPath)) { $null } else { [System.IO.Path]::GetFullPath($CurrentPath).TrimEnd('\') }
    resolveProjectMs = [int64]$ResolveProjectMs
    writeMetadataMs  = [int64]$WriteMetadataMs
    status           = $Status
    error            = if ([string]::IsNullOrWhiteSpace($ErrorMessage)) { $null } else { $ErrorMessage }
  }

  Write-EccMetricsRecord -Record $record -Path $MetricsPath
}

function Get-StableLifecycleErrorMessage {
  param(
    [string]$Status,
    [string]$EventName,
    [string]$ProjectKey,
    [string]$CurrentPath
  )

  switch ($Status) {
    'unresolved' {
      return "could not resolve memory project for '$CurrentPath'."
    }
    'metadataWriteFailed' {
      if ([string]::IsNullOrWhiteSpace($ProjectKey)) {
        return "failed to write session metadata during '$EventName'."
      }

      return "failed to write session metadata for project '$ProjectKey' during '$EventName'."
    }
    'hookFailed' {
      return "hook execution failed for '$CurrentPath' during '$EventName'."
    }
    default {
      return $null
    }
  }
}
