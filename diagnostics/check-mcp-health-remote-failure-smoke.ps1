$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot 'check-mcp-health.ps1'

if (-not (Test-Path $scriptPath)) {
  throw "Missing script: $scriptPath"
}

function Assert-Equal {
  param(
    $Actual,
    $Expected,
    [string]$Message
  )

  if ($Actual -ne $Expected) {
    throw "$Message. Expected '$Expected', got '$Actual'"
  }
}

function Assert-NotNull {
  param(
    $Value,
    [string]$Message
  )

  if ($null -eq $Value) {
    throw $Message
  }

  if ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value)) {
    throw $Message
  }
}

$fixtureRoot = Join-Path $PSScriptRoot '_check-mcp-health-remote-failure'
$localPath = Join-Path $fixtureRoot 'mcp-config.json'
$remotePath = Join-Path $fixtureRoot 'mcp-config.remote.json'
$rulesPath = Join-Path $fixtureRoot 'mcp-health-rules.json'
$outputPath = Join-Path $fixtureRoot 'mcp-health.json'

if (Test-Path $fixtureRoot) {
  Remove-Item -Path $fixtureRoot -Recurse -Force
}

New-Item -ItemType Directory -Path $fixtureRoot | Out-Null

try {
  @'
{
  "mcpServers": {}
}
'@ | Set-Content -Path $localPath -Encoding UTF8

  @'
{
  "mcpServers": {
    "remote-bad": {
      "type": "http",
      "url": "http://127.0.0.1:9/mcp"
    }
  }
}
'@ | Set-Content -Path $remotePath -Encoding UTF8

  @'
{
  "defaults": {
    "localMissingAction": "repair local dependency",
    "remoteSkippedAction": "skip remote probe",
    "remoteFailedAction": "check remote service"
  },
  "overrides": {}
}
'@ | Set-Content -Path $rulesPath -Encoding UTF8

  $health = & $scriptPath `
    -LocalMcpPath $localPath `
    -RemoteMcpPath $remotePath `
    -RulesPath $rulesPath `
    -OutputPath $outputPath | ConvertFrom-Json

  $results = @($health.results | Where-Object { $_.name -eq 'remote-bad' })
  if ($results.Count -ne 1) {
    throw "Expected exactly one result named 'remote-bad', got $($results.Count)"
  }

  $remoteBad = $results[0]
  Assert-Equal -Actual $remoteBad.type -Expected 'remote' -Message 'remote-bad type mismatch'
  Assert-Equal -Actual $remoteBad.status -Expected 'unavailable' -Message 'remote-bad status mismatch'
  Assert-Equal -Actual $remoteBad.suggestedAction -Expected 'check remote service' -Message 'remote-bad suggestedAction mismatch'
  Assert-NotNull -Value $remoteBad.error -Message 'Missing remote-bad error'
}
finally {
  if (Test-Path $fixtureRoot) {
    Remove-Item -Path $fixtureRoot -Recurse -Force
  }
}

Write-Host 'check-mcp-health remote-failure smoke PASS'
