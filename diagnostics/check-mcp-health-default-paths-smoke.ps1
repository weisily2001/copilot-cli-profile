$ErrorActionPreference = 'Stop'
$fixtureRoot = Join-Path $PSScriptRoot '_check-mcp-health-default-paths'
$fixtureDiag = Join-Path $fixtureRoot 'diagnostics'
$scriptPath = Join-Path $fixtureDiag 'check-mcp-health.ps1'
$brokenScriptPath = Join-Path $fixtureDiag 'broken-check-mcp-health.ps1'
$expectedOutput = Join-Path $fixtureRoot 'mcp-health.json'
$wrongOutput = Join-Path $fixtureDiag 'mcp-health.json'

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

function Invoke-DefaultPathsCase {
  param(
    [string]$CandidateScriptPath
  )

  foreach ($path in @($expectedOutput, $wrongOutput)) {
    if (Test-Path $path) {
      Remove-Item -Path $path -Force
    }
  }

  & $CandidateScriptPath -SkipHttpProbe | Out-Null

  if (-not (Test-Path $expectedOutput)) {
    throw "Expected output at $expectedOutput"
  }

  if ($wrongOutput -ne $expectedOutput -and (Test-Path $wrongOutput)) {
    throw "Expected no output at $wrongOutput"
  }
}

if (Test-Path $fixtureRoot) {
  Remove-Item -Path $fixtureRoot -Recurse -Force
}

New-Item -ItemType Directory -Path $fixtureDiag -Force | Out-Null

try {
  $sourceScriptPath = Join-Path $PSScriptRoot 'check-mcp-health.ps1'
  $sourceScript = Get-Content -Path $sourceScriptPath -Raw
  $brokenScript = $sourceScript.Replace(
    "  `$OutputPath = Join-Path `$repoRoot 'mcp-health.json'",
    "  `$OutputPath = Join-Path `$PSScriptRoot 'mcp-health.json'"
  )

  if ($brokenScript -eq $sourceScript) {
    throw 'Failed to inject broken default OutputPath behavior'
  }

  $sourceScript | Set-Content -Path $scriptPath -Encoding UTF8
  $brokenScript | Set-Content -Path $brokenScriptPath -Encoding UTF8

  @'
{"mcpServers":{"memory":{"type":"local","command":"powershell"}}}
'@ | Set-Content -Path (Join-Path $fixtureRoot 'mcp-config.json') -Encoding UTF8

  @'
{"mcpServers":{"context7":{"type":"http","url":"https://example.invalid/mcp"}}}
'@ | Set-Content -Path (Join-Path $fixtureRoot 'mcp-config.remote.json') -Encoding UTF8

  @'
{"defaults":{"localMissingAction":"fix local","remoteSkippedAction":"skip remote","remoteFailedAction":"check remote"}}
'@ | Set-Content -Path (Join-Path $fixtureRoot 'mcp-health-rules.json') -Encoding UTF8

  Assert-Rejects -Name 'broken default output path' {
    Invoke-DefaultPathsCase -CandidateScriptPath $brokenScriptPath
  }

  if (Test-Path $expectedOutput) {
    throw "Broken script unexpectedly wrote repo-root output to $expectedOutput"
  }

  if (-not (Test-Path $wrongOutput)) {
    throw "Broken script did not expose wrong output path at $wrongOutput"
  }

  Invoke-DefaultPathsCase -CandidateScriptPath $scriptPath
}
finally {
  if (Test-Path $fixtureRoot) {
    Remove-Item -Path $fixtureRoot -Recurse -Force
  }
}

Write-Host 'check-mcp-health default paths smoke PASS'
