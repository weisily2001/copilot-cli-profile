$ErrorActionPreference = 'Stop'
$fixtureRoot = Join-Path $env:TEMP 'copilot-cli-mcp-health-default-paths-smoke'
$fixtureDiag = Join-Path $fixtureRoot 'diagnostics'

if (Test-Path $fixtureRoot) {
  Remove-Item $fixtureRoot -Recurse -Force
}

New-Item -ItemType Directory -Path $fixtureDiag -Force | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'check-mcp-health.ps1') (Join-Path $fixtureDiag 'check-mcp-health.ps1')

@'
{"mcpServers":{"memory":{"type":"local","command":"powershell"}}}
'@ | Set-Content (Join-Path $fixtureRoot 'mcp-config.json') -Encoding UTF8

@'
{"mcpServers":{"context7":{"type":"http","url":"https://example.invalid/mcp"}}}
'@ | Set-Content (Join-Path $fixtureRoot 'mcp-config.remote.json') -Encoding UTF8

@'
{"defaults":{"localMissingAction":"fix local","remoteSkippedAction":"skip remote","remoteFailedAction":"check remote"}}
'@ | Set-Content (Join-Path $fixtureRoot 'mcp-health-rules.json') -Encoding UTF8

try {
  & (Join-Path $fixtureDiag 'check-mcp-health.ps1') -SkipHttpProbe | Out-Null

  $expectedOutput = Join-Path $fixtureRoot 'mcp-health.json'
  if (-not (Test-Path $expectedOutput)) {
    throw "Expected output at $expectedOutput"
  }
}
finally {
  if (Test-Path $fixtureRoot) {
    Remove-Item $fixtureRoot -Recurse -Force
  }
}

Write-Host 'check-mcp-health default paths smoke PASS'
