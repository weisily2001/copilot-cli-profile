$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot 'inspect-profiles.ps1'

if (-not (Test-Path $scriptPath)) {
  throw "Missing script: $scriptPath"
}

$result = & $scriptPath | ConvertFrom-Json

if ($result.profileCount -ne 3) {
  throw "Expected 3 profiles, got $($result.profileCount)"
}

foreach ($profileName in @('default', 'research', 'heavy')) {
  if ($profileName -notin $result.profileNames) {
    throw "Missing profile '$profileName'"
  }
}

if ($result.errorCount -ne 0) {
  throw "Expected errorCount 0, got $($result.errorCount)"
}

$fixtureRoot = Join-Path $PSScriptRoot '_inspect-profiles-smoke'
$fixtureProfilesPath = Join-Path $fixtureRoot 'profiles.json'
$fixtureLocalMcpPath = Join-Path $fixtureRoot 'mcp-config.json'
$fixtureRemoteMcpPath = Join-Path $fixtureRoot 'mcp-config.remote.json'
$fixtureLspPath = Join-Path $fixtureRoot 'lsp-config.json'

if (Test-Path $fixtureRoot) {
  Remove-Item -Path $fixtureRoot -Recurse -Force
}

New-Item -ItemType Directory -Path $fixtureRoot | Out-Null

try {
@'
{
  "profiles": {
    "default": {
      "description": "fixture",
      "mcpGroups": ["core-local"],
      "lspGroups": ["docs"]
    }
  },
  "mcpGroups": {
    "core-local": ["missing-mcp-server"]
  },
  "lspGroups": {
    "docs": ["json"]
  }
}
'@ | Set-Content -Path $fixtureProfilesPath -Encoding utf8

@'
{
  "mcpServers": {
    "memory": {}
  }
}
'@ | Set-Content -Path $fixtureLocalMcpPath -Encoding utf8

@'
{
  "mcpServers": {}
}
'@ | Set-Content -Path $fixtureRemoteMcpPath -Encoding utf8

@'
{
  "lspServers": {
    "typescript": {}
  }
}
'@ | Set-Content -Path $fixtureLspPath -Encoding utf8

$invalidResult = & $scriptPath `
  -ProfilesPath $fixtureProfilesPath `
  -LocalMcpPath $fixtureLocalMcpPath `
  -RemoteMcpPath $fixtureRemoteMcpPath `
  -LspPath $fixtureLspPath | ConvertFrom-Json

if ($invalidResult.errorCount -lt 2) {
  throw "Expected multiple validation errors for fixture profile, got $($invalidResult.errorCount)"
}

if ("Unknown MCP server 'missing-mcp-server' in group 'core-local' for profile 'default'" -notin $invalidResult.errors) {
  throw "Expected missing MCP server error, got: $($invalidResult.errors -join '; ')"
}

if ("Unknown LSP server 'json' in group 'docs' for profile 'default'" -notin $invalidResult.errors) {
  throw "Expected missing LSP server error, got: $($invalidResult.errors -join '; ')"
}

@'
{
  "profiles": {
    "default": {
      "description": "fixture"
    }
  }
}
'@ | Set-Content -Path $fixtureProfilesPath -Encoding utf8

$schemaResult = & $scriptPath `
  -ProfilesPath $fixtureProfilesPath `
  -LocalMcpPath $fixtureLocalMcpPath `
  -RemoteMcpPath $fixtureRemoteMcpPath `
  -LspPath $fixtureLspPath | ConvertFrom-Json

if ($schemaResult.profileCount -ne 1) {
  throw "Expected profileCount 1 for schema fixture, got $($schemaResult.profileCount)"
}

if ('default' -notin $schemaResult.profileNames) {
  throw "Expected schema fixture to keep profile name, got: $($schemaResult.profileNames -join ', ')"
}

foreach ($expectedError in @(
  'Missing profiles.mcpGroups',
  'Missing profiles.lspGroups',
  "Profile 'default' is missing mcpGroups",
  "Profile 'default' is missing lspGroups"
)) {
  if ($expectedError -notin $schemaResult.errors) {
    throw "Expected schema validation error '$expectedError', got: $($schemaResult.errors -join '; ')"
  }
}
}
finally {
  if (Test-Path $fixtureRoot) {
    Remove-Item -Path $fixtureRoot -Recurse -Force
  }
}

Write-Host 'inspect-profiles smoke PASS'
