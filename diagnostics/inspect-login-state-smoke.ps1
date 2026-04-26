$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot 'inspect-login-state.ps1'

if (-not (Test-Path $scriptPath)) {
  throw "Missing script: $scriptPath"
}

$result = & $scriptPath | ConvertFrom-Json

if (-not $result.PSObject.Properties['hasCachedLogin']) {
  throw 'Missing hasCachedLogin'
}

if (-not $result.PSObject.Properties['lastLoginHost']) {
  throw 'Missing lastLoginHost'
}

if (-not $result.PSObject.Properties['lastLoginUser']) {
  throw 'Missing lastLoginUser'
}

if (-not $result.PSObject.Properties['trustedFolders']) {
  throw 'Missing trustedFolders'
}

Write-Host 'inspect-login-state smoke PASS'
