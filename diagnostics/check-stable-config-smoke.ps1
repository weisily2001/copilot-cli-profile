$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent

$settings = Get-Content (Join-Path $repoRoot 'settings.json') -Raw | ConvertFrom-Json
$profiles = Get-Content (Join-Path $repoRoot 'profiles.json') -Raw | ConvertFrom-Json
$lsp = Get-Content (Join-Path $repoRoot 'lsp-config.json') -Raw | ConvertFrom-Json

$forbiddenSettingsKeys = @(
  'firstLaunchAt',
  'askedSetupTerminals',
  'lastLoggedInUser',
  'loggedInUsers',
  'trustedFolders'
)

foreach ($key in $forbiddenSettingsKeys) {
  if ($settings.PSObject.Properties.Name -contains $key) {
    throw "settings.json should not keep host/runtime key '$key'"
  }
}

foreach ($profileName in @('default', 'research', 'heavy')) {
  $profile = $profiles.profiles.$profileName
  if ($null -eq $profile) {
    throw "Missing profile '$profileName'"
  }

  foreach ($group in @($profile.lspGroups)) {
    if ($group -ne 'core') {
      throw "Profile '$profileName' should only reference stable lsp group 'core', got '$group'"
    }
  }
}

$lspServers = @($lsp.lspServers.PSObject.Properties.Name)
if (@('typescript', 'python') | Where-Object { $_ -notin $lspServers }) {
  throw 'lsp-config.json must keep typescript and python'
}

Write-Host 'check-stable-config smoke PASS'
