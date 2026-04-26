param()

$ErrorActionPreference = 'Stop'
$currentPath = (Get-Location).Path
$sharedLoaded = $false

function Write-BootstrapFailureMetric {
  param(
    [string]$EventName,
    [string]$CurrentPath,
    [string]$ErrorMessage
  )

  $copilotHome = Join-Path $HOME '.copilot'
  $metricsPath = if (-not [string]::IsNullOrWhiteSpace($env:COPILOT_ECC_MEMORY_METRICS_PATH)) { $env:COPILOT_ECC_MEMORY_METRICS_PATH } else { Join-Path $copilotHome 'hook-metrics.jsonl' }
  $keepLast = 100
  if (-not [string]::IsNullOrWhiteSpace($env:COPILOT_ECC_MEMORY_METRICS_KEEP_LAST)) {
    try {
      $parsedKeepLast = [int]$env:COPILOT_ECC_MEMORY_METRICS_KEEP_LAST
      if ($parsedKeepLast -gt 0) {
        $keepLast = $parsedKeepLast
      }
    }
    catch {
    }
  }

  $metricsDir = Split-Path $metricsPath -Parent
  if (-not [string]::IsNullOrWhiteSpace($metricsDir)) {
    [System.IO.Directory]::CreateDirectory($metricsDir) | Out-Null
  }

  $record = [ordered]@{
    timestamp        = (Get-Date).ToString('o')
    event            = $EventName
    projectKey       = $null
    projectRoot      = $null
    projectDir       = $null
    currentPath      = if ([string]::IsNullOrWhiteSpace($CurrentPath)) { $null } else { [System.IO.Path]::GetFullPath($CurrentPath).TrimEnd('\') }
    resolveProjectMs = [int64]0
    writeMetadataMs  = [int64]0
    status           = 'hookFailed'
    error            = $ErrorMessage
  }

  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::AppendAllText($metricsPath, ($record | ConvertTo-Json -Depth 5 -Compress) + [Environment]::NewLine, $utf8NoBom)

  $lines = @(Get-Content -Path $metricsPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  if ($lines.Count -gt $keepLast) {
    [System.IO.File]::WriteAllLines($metricsPath, ($lines | Select-Object -Last $keepLast), $utf8NoBom)
  }
}

function Get-StableBootstrapErrorMessage {
  param(
    [string]$EventName,
    [string]$CurrentPath
  )

  return "failed to bootstrap shared hook dependencies for '$CurrentPath' during '$EventName'."
}

try {
  . (Join-Path $HOME '.copilot\hooks\ecc-memory\shared.ps1')
  $sharedLoaded = $true

  $project = $null
  $writeMetadataMs = 0
  $resolveProjectMs = 0
  $status = 'hookFailed'
  $errorMessage = $null
  $resolveStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

  try {
    $project = Resolve-ProjectContextFast -Path $currentPath
    $resolveStopwatch.Stop()
    $resolveProjectMs = $resolveStopwatch.ElapsedMilliseconds

    if ($null -eq $project) {
      $status = 'unresolved'
      $errorMessage = "could not resolve memory project for '$currentPath'."
      [Console]::Error.WriteLine("Warning: $errorMessage")
    }
    else {
      try {
        $writeMetadataMs = Write-LastSessionMetadata -ProjectKey $project.ProjectKey -ProjectRoot $project.ProjectRoot -ProjectDir $project.ProjectDir -EventName 'sessionEnd'
        $status = 'success'
      }
      catch {
        $status = 'metadataWriteFailed'
        $errorMessage = Get-StableLifecycleErrorMessage -Status $status -EventName 'sessionEnd' -ProjectKey $project.ProjectKey -CurrentPath $currentPath
        [Console]::Error.WriteLine("Warning: session-end hook failed: $($_.Exception.Message)")
      }
    }
  }
  catch {
    if ($resolveStopwatch.IsRunning) {
      $resolveStopwatch.Stop()
    }

    $resolveProjectMs = $resolveStopwatch.ElapsedMilliseconds
    $status = 'hookFailed'
    $errorMessage = Get-StableLifecycleErrorMessage -Status $status -EventName 'sessionEnd' -ProjectKey $project.ProjectKey -CurrentPath $currentPath
    [Console]::Error.WriteLine("Warning: session-end hook failed: $($_.Exception.Message)")
  }
  finally {
    try {
      Write-ProjectLifecycleMetrics -EventName 'sessionEnd' -ProjectKey $project.ProjectKey -ProjectRoot $project.ProjectRoot -ProjectDir $project.ProjectDir -CurrentPath $currentPath -ResolveProjectMs $resolveProjectMs -WriteMetadataMs $writeMetadataMs -Status $status -ErrorMessage $errorMessage
    }
    catch {
      [Console]::Error.WriteLine("Warning: failed to write session-end metrics: $($_.Exception.Message)")
    }
  }
}
catch {
  [Console]::Error.WriteLine("Warning: session-end hook failed: $($_.Exception.Message)")
  if (-not $sharedLoaded) {
    try {
      Write-BootstrapFailureMetric -EventName 'sessionEnd' -CurrentPath $currentPath -ErrorMessage (Get-StableBootstrapErrorMessage -EventName 'sessionEnd' -CurrentPath $currentPath)
    }
    catch {
      [Console]::Error.WriteLine("Warning: failed to write session-end bootstrap metrics: $($_.Exception.Message)")
    }
  }
}
finally {
  Write-Output '{"continue":true}'
}
