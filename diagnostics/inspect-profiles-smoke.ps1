$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot 'inspect-profiles.ps1'

if (-not (Test-Path $scriptPath)) {
  throw "Missing script: $scriptPath"
}

function Get-Errors {
  param($Result)

  if ($null -eq $Result.errors) {
    return @()
  }

  return @($Result.errors)
}

function Format-Errors {
  param($Result)

  $lines = @(Get-Errors -Result $Result | ForEach-Object {
      "$($_.path)|$($_.code)|$($_.message)"
    })

  if ($lines.Count -eq 0) {
    return '<none>'
  }

  return $lines -join '; '
}

function Assert-HasError {
  param(
    $Result,
    [string]$Path,
    [string]$Code,
    [string]$Message
  )

  $matches = @(Get-Errors -Result $Result | Where-Object {
      $_.path -eq $Path -and $_.code -eq $Code -and $_.message -eq $Message
    })

  if ($matches.Count -eq 0) {
    throw "Expected error '$Path|$Code|$Message', got: $(Format-Errors -Result $Result)"
  }
}

function Assert-NoErrorMessageLike {
  param(
    $Result,
    [string]$Pattern,
    [string]$Context
  )

  $matches = @(Get-Errors -Result $Result | Where-Object { $_.message -match $Pattern })
  if ($matches.Count -gt 0) {
    throw "$Context should not include messages matching '$Pattern', got: $(Format-Errors -Result $Result)"
  }
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
  throw "Expected errorCount 0, got $($result.errorCount): $(Format-Errors -Result $result)"
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

  Assert-HasError -Result $invalidResult `
    -Path 'profiles.mcpGroups.core-local[0]' `
    -Code 'unknown-reference' `
    -Message "profiles.mcpGroups.core-local[0] references unknown MCP server 'missing-mcp-server' for profile 'default'"

  Assert-HasError -Result $invalidResult `
    -Path 'profiles.lspGroups.docs[0]' `
    -Code 'unknown-reference' `
    -Message "profiles.lspGroups.docs[0] references unknown LSP server 'json' for profile 'default'"

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

  Assert-HasError -Result $schemaResult -Path 'profiles.mcpGroups' -Code 'missing-property' -Message 'profiles.mcpGroups is required'
  Assert-HasError -Result $schemaResult -Path 'profiles.lspGroups' -Code 'missing-property' -Message 'profiles.lspGroups is required'
  Assert-HasError -Result $schemaResult -Path 'profiles.profiles.default.mcpGroups' -Code 'missing-property' -Message 'profiles.profiles.default.mcpGroups is required'
  Assert-HasError -Result $schemaResult -Path 'profiles.profiles.default.lspGroups' -Code 'missing-property' -Message 'profiles.profiles.default.lspGroups is required'

@'
{
  "profiles": ["wrong"],
  "mcpGroups": ["wrong"],
  "lspGroups": ["wrong"]
}
'@ | Set-Content -Path $fixtureProfilesPath -Encoding utf8

  $wrongTypeRootResult = & $scriptPath `
    -ProfilesPath $fixtureProfilesPath `
    -LocalMcpPath $fixtureLocalMcpPath `
    -RemoteMcpPath $fixtureRemoteMcpPath `
    -LspPath $fixtureLspPath | ConvertFrom-Json

  Assert-HasError -Result $wrongTypeRootResult -Path 'profiles.profiles' -Code 'invalid-type' -Message 'profiles.profiles must be an object'
  Assert-HasError -Result $wrongTypeRootResult -Path 'profiles.mcpGroups' -Code 'invalid-type' -Message 'profiles.mcpGroups must be an object'
  Assert-HasError -Result $wrongTypeRootResult -Path 'profiles.lspGroups' -Code 'invalid-type' -Message 'profiles.lspGroups must be an object'

  if ($wrongTypeRootResult.profileCount -ne 0) {
    throw "Expected wrong-type root fixture to expose 0 profiles, got $($wrongTypeRootResult.profileCount)"
  }

  if ($wrongTypeRootResult.profileNames.Count -ne 0) {
    throw "Expected wrong-type root fixture to avoid bogus profile names, got: $($wrongTypeRootResult.profileNames -join ', ')"
  }

  Assert-NoErrorMessageLike -Result $wrongTypeRootResult -Pattern "'(Length|LongLength|Rank|SyncRoot|IsReadOnly|IsFixedSize|IsSynchronized|Count)'" -Context 'Wrong-type root fixture'

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
    "core-local": ["Length"]
  },
  "lspGroups": {
    "docs": ["typescript"]
  }
}
'@ | Set-Content -Path $fixtureProfilesPath -Encoding utf8

@'
{
  "mcpServers": []
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

  $wrongTypeMcpRootResult = & $scriptPath `
    -ProfilesPath $fixtureProfilesPath `
    -LocalMcpPath $fixtureLocalMcpPath `
    -RemoteMcpPath $fixtureRemoteMcpPath `
    -LspPath $fixtureLspPath | ConvertFrom-Json

  Assert-HasError -Result $wrongTypeMcpRootResult -Path 'localMcp.mcpServers' -Code 'invalid-type' -Message 'localMcp.mcpServers must be an object'
  Assert-HasError -Result $wrongTypeMcpRootResult `
    -Path 'profiles.mcpGroups.core-local[0]' `
    -Code 'unknown-reference' `
    -Message "profiles.mcpGroups.core-local[0] references unknown MCP server 'Length' for profile 'default'"

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
    "docs": ["Count"]
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
  "lspServers": []
}
'@ | Set-Content -Path $fixtureLspPath -Encoding utf8

  $wrongTypeLspRootResult = & $scriptPath `
    -ProfilesPath $fixtureProfilesPath `
    -LocalMcpPath $fixtureLocalMcpPath `
    -RemoteMcpPath $fixtureRemoteMcpPath `
    -LspPath $fixtureLspPath | ConvertFrom-Json

  Assert-HasError -Result $wrongTypeLspRootResult -Path 'lsp.lspServers' -Code 'invalid-type' -Message 'lsp.lspServers must be an object'
  Assert-HasError -Result $wrongTypeLspRootResult `
    -Path 'profiles.lspGroups.docs[0]' `
    -Code 'unknown-reference' `
    -Message "profiles.lspGroups.docs[0] references unknown LSP server 'Count' for profile 'default'"

@'
{
  "profiles": {
    "default": ["wrong"]
  },
  "mcpGroups": {},
  "lspGroups": {}
}
'@ | Set-Content -Path $fixtureProfilesPath -Encoding utf8

  $wrongTypeProfileResult = & $scriptPath `
    -ProfilesPath $fixtureProfilesPath `
    -LocalMcpPath $fixtureLocalMcpPath `
    -RemoteMcpPath $fixtureRemoteMcpPath `
    -LspPath $fixtureLspPath | ConvertFrom-Json

  Assert-HasError -Result $wrongTypeProfileResult -Path 'profiles.profiles.default' -Code 'invalid-type' -Message 'profiles.profiles.default must be an object'
  Assert-NoErrorMessageLike -Result $wrongTypeProfileResult -Pattern 'profiles\.profiles\.default\.(mcpGroups|lspGroups)' -Context 'Wrong-type profile fixture'

@'
{
  "profiles": {
    "default": {
      "description": "fixture",
      "mcpGroups": "core-local",
      "lspGroups": {}
    }
  },
  "mcpGroups": {
    "core-local": ["memory"]
  },
  "lspGroups": {
    "docs": ["typescript"]
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

  $wrongTypeProfileGroupsResult = & $scriptPath `
    -ProfilesPath $fixtureProfilesPath `
    -LocalMcpPath $fixtureLocalMcpPath `
    -RemoteMcpPath $fixtureRemoteMcpPath `
    -LspPath $fixtureLspPath | ConvertFrom-Json

  Assert-HasError -Result $wrongTypeProfileGroupsResult `
    -Path 'profiles.profiles.default.mcpGroups' `
    -Code 'invalid-type' `
    -Message 'profiles.profiles.default.mcpGroups must be an array of strings'

  Assert-HasError -Result $wrongTypeProfileGroupsResult `
    -Path 'profiles.profiles.default.lspGroups' `
    -Code 'invalid-type' `
    -Message 'profiles.profiles.default.lspGroups must be an array of strings'

  Assert-NoErrorMessageLike -Result $wrongTypeProfileGroupsResult -Pattern 'unknown (MCP|LSP) group' -Context 'Wrong-type profile group fixture'

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
    "core-local": "memory"
  },
  "lspGroups": {
    "docs": {
      "primary": "typescript"
    }
  }
}
'@ | Set-Content -Path $fixtureProfilesPath -Encoding utf8

  $wrongTypeGroupNodesResult = & $scriptPath `
    -ProfilesPath $fixtureProfilesPath `
    -LocalMcpPath $fixtureLocalMcpPath `
    -RemoteMcpPath $fixtureRemoteMcpPath `
    -LspPath $fixtureLspPath | ConvertFrom-Json

  Assert-HasError -Result $wrongTypeGroupNodesResult `
    -Path 'profiles.mcpGroups.core-local' `
    -Code 'invalid-type' `
    -Message 'profiles.mcpGroups.core-local must be an array of strings'

  Assert-HasError -Result $wrongTypeGroupNodesResult `
    -Path 'profiles.lspGroups.docs' `
    -Code 'invalid-type' `
    -Message 'profiles.lspGroups.docs must be an array of strings'

  Assert-NoErrorMessageLike -Result $wrongTypeGroupNodesResult -Pattern 'unknown (MCP|LSP) server' -Context 'Wrong-type group-node fixture'
}
finally {
  if (Test-Path $fixtureRoot) {
    Remove-Item -Path $fixtureRoot -Recurse -Force
  }
}

Write-Host 'inspect-profiles smoke PASS'
