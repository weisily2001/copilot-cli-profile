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

function Assert-NullOrEmpty {
  param(
    $Value,
    [string]$Message
  )

  if ($null -ne $Value -and (-not ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value)))) {
    throw "$Message. Expected null or empty, got '$Value'"
  }
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

$fixtureRoot = Join-Path $PSScriptRoot '_check-mcp-health-smoke'
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
  "mcpServers": {
    "local-good": {
      "type": "local",
      "command": "powershell"
    },
    "local-missing": {
      "type": "local",
      "command": "command-that-should-not-exist-12345"
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
    "localMissingAction": "install local dependency",
    "remoteSkippedAction": "enable probe later",
    "remoteFailedAction": "check remote service"
  },
  "overrides": {
    "context7": {
      "suggestedAction": "use docs fallback"
    },
    "exa": {
      "suggestedAction": "disable research enhancement"
    },
    "local-missing": {
      "suggestedAction": "repair missing local command"
    },
    "remote-skip": {
      "suggestedAction": "defer remote probe for smoke"
    }
  }
}
'@ | Set-Content -Path $rulesPath -Encoding UTF8

  $health = & $scriptPath `
    -LocalMcpPath $localPath `
    -RemoteMcpPath $remotePath `
    -RulesPath $rulesPath `
    -OutputPath $outputPath `
    -SkipHttpProbe | ConvertFrom-Json

  Assert-NotNull -Value $health.generatedAt -Message 'Missing generatedAt'

  $localGood = Get-ResultByName -Health $health -Name 'local-good'
  Assert-Equal -Actual $localGood.type -Expected 'local' -Message 'local-good type mismatch'
  Assert-Equal -Actual $localGood.status -Expected 'healthy' -Message 'local-good status mismatch'
  Assert-NullOrEmpty -Value $localGood.suggestedAction -Message 'local-good suggestedAction mismatch'
  Assert-NotNull -Value $localGood.checkedAt -Message 'Missing local-good checkedAt'

  $localMissing = Get-ResultByName -Health $health -Name 'local-missing'
  Assert-Equal -Actual $localMissing.type -Expected 'local' -Message 'local-missing type mismatch'
  Assert-Equal -Actual $localMissing.status -Expected 'unavailable' -Message 'local-missing status mismatch'
  Assert-Equal -Actual $localMissing.suggestedAction -Expected 'repair missing local command' -Message 'local-missing suggestedAction mismatch'
  Assert-NotNull -Value $localMissing.error -Message 'Missing local-missing error'

  $remoteSkip = Get-ResultByName -Health $health -Name 'remote-skip'
  Assert-Equal -Actual $remoteSkip.type -Expected 'remote' -Message 'remote-skip type mismatch'
  Assert-Equal -Actual $remoteSkip.status -Expected 'degraded' -Message 'remote-skip status mismatch'
  Assert-Equal -Actual $remoteSkip.suggestedAction -Expected 'defer remote probe for smoke' -Message 'remote-skip suggestedAction mismatch'
  Assert-NotNull -Value $remoteSkip.checkedAt -Message 'Missing remote-skip checkedAt'

  if (-not (Test-Path $outputPath)) {
    throw "Expected output file: $outputPath"
  }

  $saved = Get-Content -Path $outputPath -Raw | ConvertFrom-Json
  if (@($saved.results).Count -ne 3) {
    throw "Expected 3 saved results, got $(@($saved.results).Count)"
  }
}
finally {
  if (Test-Path $fixtureRoot) {
    Remove-Item -Path $fixtureRoot -Recurse -Force
  }
}

Write-Host 'check-mcp-health smoke PASS'
