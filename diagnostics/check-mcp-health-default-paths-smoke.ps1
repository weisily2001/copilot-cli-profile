$ErrorActionPreference = 'Stop'
$sourceScriptPath = Join-Path $PSScriptRoot 'check-mcp-health.ps1'

if (-not (Test-Path $sourceScriptPath)) {
  throw "Missing script: $sourceScriptPath"
}

function Assert-True {
  param(
    [bool]$Condition,
    [string]$Message
  )

  if (-not $Condition) {
    throw $Message
  }
}

$fixtureRoot = Join-Path $env:TEMP 'copilot-mcp-health-default-paths-smoke'
$repoRoot = Join-Path $fixtureRoot 'repo'
$diagnosticsRoot = Join-Path $repoRoot 'diagnostics'
$scriptPath = Join-Path $diagnosticsRoot 'check-mcp-health.ps1'
$localPath = Join-Path $repoRoot 'mcp-config.json'
$remotePath = Join-Path $repoRoot 'mcp-config.remote.json'
$rulesPath = Join-Path $repoRoot 'mcp-health-rules.json'
$outputPath = Join-Path $repoRoot 'mcp-health.json'
if (Test-Path $fixtureRoot) {
  Remove-Item -Path $fixtureRoot -Recurse -Force
}

New-Item -ItemType Directory -Path $diagnosticsRoot -Force | Out-Null
Copy-Item -Path $sourceScriptPath -Destination $scriptPath

try {
  @'
{
  "mcpServers": {
    "local-good": {
      "type": "local",
      "command": "powershell"
    }
  }
}
'@ | Set-Content -Path $localPath -Encoding UTF8

  @'
{
  "mcpServers": {
    "remote-skip": {
      "type": "http",
      "url": "https://example.invalid/mcp"
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
    -SkipHttpProbe | ConvertFrom-Json

  Assert-True -Condition ($null -ne $health.generatedAt) -Message 'Missing generatedAt'
  Assert-True -Condition (Test-Path $outputPath) -Message "Expected output file at repo root: $outputPath"
}
finally {
  if (Test-Path $fixtureRoot) {
    Remove-Item -Path $fixtureRoot -Recurse -Force
  }
}

Write-Host 'check-mcp-health default-paths smoke PASS'
