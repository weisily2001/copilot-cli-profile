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

Write-Host 'inspect-profiles smoke PASS'
