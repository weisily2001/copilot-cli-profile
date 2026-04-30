$ErrorActionPreference = 'Stop'
$fixtureRoot = Join-Path $PSScriptRoot '_check-mcp-health-remote-failure'
$localPath = Join-Path $fixtureRoot 'mcp-config.json'
$remotePath = Join-Path $fixtureRoot 'mcp-config.remote.json'
$rulesPath = Join-Path $fixtureRoot 'mcp-health-rules.json'
$outputPath = Join-Path $fixtureRoot 'mcp-health.json'

if (Test-Path $fixtureRoot) {
  Remove-Item $fixtureRoot -Recurse -Force
}

New-Item -ItemType Directory -Path $fixtureRoot | Out-Null

try {
  '{"mcpServers":{"memory":{"type":"local","command":"powershell"}}}' | Set-Content $localPath -Encoding UTF8
  '{"mcpServers":{"context7":{"type":"http","url":"https://example.invalid/mcp"}}}' | Set-Content $remotePath -Encoding UTF8
  '{"defaults":{"localMissingAction":"fix local","remoteSkippedAction":"skip remote","remoteFailedAction":"check remote"}}' | Set-Content $rulesPath -Encoding UTF8

  $health = & (Join-Path $PSScriptRoot 'check-mcp-health.ps1') -LocalMcpPath $localPath -RemoteMcpPath $remotePath -RulesPath $rulesPath -OutputPath $outputPath | ConvertFrom-Json
  $result = @($health.results | Where-Object { $_.name -eq 'context7' })[0]

  if ($result.status -ne 'unavailable') {
    throw "Expected remote failure to normalize to unavailable, got '$($result.status)'"
  }
}
finally {
  if (Test-Path $fixtureRoot) {
    Remove-Item $fixtureRoot -Recurse -Force
  }
}

Write-Host 'check-mcp-health remote failure smoke PASS'
