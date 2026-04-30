$ErrorActionPreference = 'Stop'
$fixtureRoot = Join-Path $PSScriptRoot '_check-mcp-health-remote-failure'
$fixtureDiag = Join-Path $fixtureRoot 'diagnostics'
$scriptPath = Join-Path $fixtureDiag 'check-mcp-health.ps1'
$brokenScriptPath = Join-Path $fixtureDiag 'broken-check-mcp-health.ps1'
$localPath = Join-Path $fixtureRoot 'mcp-config.json'
$remotePath = Join-Path $fixtureRoot 'mcp-config.remote.json'
$rulesPath = Join-Path $fixtureRoot 'mcp-health-rules.json'
$outputPath = Join-Path $fixtureRoot 'mcp-health.json'

function Assert-Rejects {
  param(
    [string]$Name,
    [scriptblock]$Action
  )

  try {
    & $Action
  }
  catch {
    return
  }

  throw "Expected failure for '$Name'"
}

function Get-ResultByName {
  param(
    $Health,
    [string]$Name
  )

  $matches = @($Health.results | Where-Object { $_.name -eq $Name })
  if ($matches.Count -ne 1) {
    throw "Expected exactly one result named '$Name', got $($matches.Count)"
  }

  return $matches[0]
}

function Invoke-HealthScript {
  param(
    [string]$CandidateScriptPath
  )

  if (Test-Path $outputPath) {
    Remove-Item -Path $outputPath -Force
  }

  return & $CandidateScriptPath -LocalMcpPath $localPath -RemoteMcpPath $remotePath -RulesPath $rulesPath -OutputPath $outputPath | ConvertFrom-Json
}

function Assert-RemoteFailureNormalized {
  param(
    $Health
  )

  $result = Get-ResultByName -Health $Health -Name 'context7'
  if ($result.status -ne 'unavailable') {
    throw "Expected remote failure to normalize to unavailable, got '$($result.status)'"
  }

  return $result
}

if (Test-Path $fixtureRoot) {
  Remove-Item -Path $fixtureRoot -Recurse -Force
}

New-Item -ItemType Directory -Path $fixtureDiag -Force | Out-Null

try {
  $sourceScriptPath = Join-Path $PSScriptRoot 'check-mcp-health.ps1'
  $sourceScript = Get-Content -Path $sourceScriptPath -Raw
  $brokenScript = $sourceScript.Replace(
    "    return New-HealthResult -Name `$Name -Type 'remote' -Status 'unavailable' -LatencyMs `$sw.ElapsedMilliseconds -CheckedAt `$checkedAt -Error `$_.Exception.Message -SuggestedAction (Get-SuggestedAction -Name `$Name -Status 'unavailable' -ServerKind 'remote' -Rules `$Rules)",
    "    return New-HealthResult -Name `$Name -Type 'remote' -Status 'degraded' -LatencyMs `$sw.ElapsedMilliseconds -CheckedAt `$checkedAt -Error `$_.Exception.Message -SuggestedAction (Get-SuggestedAction -Name `$Name -Status 'degraded' -ServerKind 'remote' -Rules `$Rules)"
  )

  if ($brokenScript -eq $sourceScript) {
    throw 'Failed to inject broken remote failure normalization behavior'
  }

  $sourceScript | Set-Content -Path $scriptPath -Encoding UTF8
  $brokenScript | Set-Content -Path $brokenScriptPath -Encoding UTF8

  '{"mcpServers":{"memory":{"type":"local","command":"powershell"}}}' | Set-Content -Path $localPath -Encoding UTF8
  '{"mcpServers":{"context7":{"type":"http","url":"https://example.invalid/mcp"}}}' | Set-Content -Path $remotePath -Encoding UTF8
  '{"defaults":{"localMissingAction":"fix local","remoteSkippedAction":"skip remote","remoteFailedAction":"check remote"}}' | Set-Content -Path $rulesPath -Encoding UTF8

  $brokenHealth = Invoke-HealthScript -CandidateScriptPath $brokenScriptPath
  $brokenResult = Get-ResultByName -Health $brokenHealth -Name 'context7'
  if ($brokenResult.status -ne 'degraded') {
    throw "Expected broken remote failure status to stay degraded, got '$($brokenResult.status)'"
  }

  Assert-Rejects -Name 'broken remote failure normalization' {
    Assert-RemoteFailureNormalized -Health $brokenHealth | Out-Null
  }

  $health = Invoke-HealthScript -CandidateScriptPath $scriptPath
  Assert-RemoteFailureNormalized -Health $health | Out-Null
}
finally {
  if (Test-Path $fixtureRoot) {
    Remove-Item -Path $fixtureRoot -Recurse -Force
  }
}

Write-Host 'check-mcp-health remote failure smoke PASS'
