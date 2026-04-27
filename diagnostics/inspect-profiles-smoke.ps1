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
$repoRoot = Split-Path $PSScriptRoot -Parent

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
    "core-local": ["memory"]
  },
  "lspGroups": {
    "docs": ["json"]
  }
}
'@ | Set-Content -Path $fixtureProfilesPath -Encoding utf8

$invalidResult = & $scriptPath `
  -ProfilesPath $fixtureProfilesPath `
  -LocalMcpPath (Join-Path $repoRoot 'mcp-config.json') `
  -RemoteMcpPath (Join-Path $repoRoot 'mcp-config.remote.json') `
  -LspPath (Join-Path $repoRoot 'lsp-config.json') | ConvertFrom-Json

if ($invalidResult.errorCount -eq 0) {
  throw 'Expected missing LSP server validation error for fixture profile'
}

if ("Unknown LSP server 'json' in group 'docs' for profile 'default'" -notin $invalidResult.errors) {
  throw "Expected missing LSP server error, got: $($invalidResult.errors -join '; ')"
}
}
finally {
  if (Test-Path $fixtureRoot) {
    Remove-Item -Path $fixtureRoot -Recurse -Force
  }
}

Write-Host 'inspect-profiles smoke PASS'
