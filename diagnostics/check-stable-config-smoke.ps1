$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent

function Get-JsonClone {
  param(
    [Parameter(Mandatory)]
    $InputObject
  )

  return ($InputObject | ConvertTo-Json -Depth 100 | ConvertFrom-Json)
}

function Format-Values {
  param(
    $Values
  )

  $stringValues = @()
  if ($null -ne $Values) {
    if ($Values -is [string]) {
      $stringValues = @([string]$Values)
    } else {
      $stringValues = @($Values | ForEach-Object { [string]$_ })
    }
  }

  if ($stringValues.Count -eq 0) {
    return '<empty>'
  }

  return ($stringValues -join ',')
}

function Assert-ExactSequence {
  param(
    [Parameter(Mandatory)]
    [string]$Name,
    [Parameter(Mandatory)]
    [string[]]$Expected,
    $Actual
  )

  $actualValues = [System.Collections.Generic.List[string]]::new()
  if ($null -ne $Actual) {
    if ($Actual -is [string]) {
      [void]$actualValues.Add([string]$Actual)
    } else {
      foreach ($item in $Actual) {
        [void]$actualValues.Add([string]$item)
      }
    }
  }

  if ($actualValues.Count -ne $Expected.Count) {
    throw "$Name should equal [$([string](Format-Values $Expected))], got [$([string](Format-Values $actualValues))]"
  }

  for ($index = 0; $index -lt $Expected.Count; $index++) {
    if ($actualValues[$index] -ne $Expected[$index]) {
      throw "$Name should equal [$([string](Format-Values $Expected))], got [$([string](Format-Values $actualValues))]"
    }
  }
}

function Assert-ExactSet {
  param(
    [Parameter(Mandatory)]
    [string]$Name,
    [Parameter(Mandatory)]
    [string[]]$Expected,
    $Actual
  )

  $expectedValues = @($Expected | Sort-Object)
  $actualValues = @()
  if ($null -ne $Actual) {
    if ($Actual -is [string]) {
      $actualValues = @([string]$Actual)
    } else {
      $actualValues = @($Actual | ForEach-Object { [string]$_ })
    }
  }

  $actualValues = @($actualValues | Sort-Object)
  Assert-ExactSequence -Name $Name -Expected $expectedValues -Actual $actualValues
}

function Assert-Rejects {
  param(
    [Parameter(Mandatory)]
    [string]$Name,
    [Parameter(Mandatory)]
    [scriptblock]$Action
  )

  try {
    & $Action
  } catch {
    return
  }

  throw "Expected validation to reject '$Name'"
}

function Test-StableSettings {
  param(
    [Parameter(Mandatory)]
    $Settings
  )

  Assert-ExactSet -Name 'settings.json top-level keys' -Expected @(
    'allowedUrls',
    'renderMarkdown',
    'respectGitignore',
    'includeCoAuthoredBy',
    'logLevel',
    'disableAllHooks',
    'hooks'
  ) -Actual (@($Settings.PSObject.Properties | ForEach-Object { [string]$_.Name }))

  Assert-ExactSet -Name 'settings.json hooks keys' -Expected @(
    'sessionStart',
    'sessionEnd'
  ) -Actual (@($Settings.hooks.PSObject.Properties | ForEach-Object { [string]$_.Name }))

  $expectedHooks = @{
    sessionStart = '& "$HOME\\.copilot\\hooks\\ecc-memory\\session-start.ps1"'
    sessionEnd = '& "$HOME\\.copilot\\hooks\\ecc-memory\\session-end.ps1"'
  }

  foreach ($hookName in $expectedHooks.Keys) {
    $entries = @($Settings.hooks.$hookName)
    if ($entries.Count -ne 1) {
      throw "Hook '$hookName' must contain exactly one command entry"
    }

    for ($index = 0; $index -lt $entries.Count; $index++) {
      $entry = $entries[$index]
      Assert-ExactSet -Name "settings.json hooks.$hookName[$index] keys" -Expected @(
        'type',
        'powershell',
        'timeoutSec'
      ) -Actual (@($entry.PSObject.Properties | ForEach-Object { [string]$_.Name }))

      if ($entry.type -ne 'command') {
        throw "Hook '$hookName' entry $index should set type=command"
      }

      if ($entry.powershell -ne $expectedHooks[$hookName]) {
        throw "Hook '$hookName' entry $index should keep powershell='$($expectedHooks[$hookName])'"
      }

      if ([int]$entry.timeoutSec -ne 3) {
        throw "Hook '$hookName' entry $index should keep timeoutSec=3"
      }
    }
  }
}

function Test-StableProfiles {
  param(
    [Parameter(Mandatory)]
    $Profiles
  )

  Assert-ExactSet -Name 'profiles.json top-level keys' -Expected @(
    'profiles',
    'mcpGroups',
    'lspGroups'
  ) -Actual (@($Profiles.PSObject.Properties | ForEach-Object { [string]$_.Name }))

  Assert-ExactSet -Name 'profiles.json profiles' -Expected @(
    'default',
    'research',
    'heavy'
  ) -Actual (@($Profiles.profiles.PSObject.Properties | ForEach-Object { [string]$_.Name }))

  $expectedProfileMcpGroups = @{
    default = @('core-local', 'core-remote')
    research = @('core-local', 'core-remote', 'research')
    heavy = @('core-local', 'core-remote', 'research', 'browser')
  }

  foreach ($profileName in $expectedProfileMcpGroups.Keys) {
    $profile = $Profiles.profiles.$profileName
    if ($null -eq $profile) {
      throw "Missing profile '$profileName'"
    }

    Assert-ExactSequence -Name "profiles.$profileName.mcpGroups" -Expected $expectedProfileMcpGroups[$profileName] -Actual $profile.mcpGroups
    Assert-ExactSequence -Name "profiles.$profileName.lspGroups" -Expected @('core') -Actual $profile.lspGroups
  }

  Assert-ExactSet -Name 'profiles.json mcpGroups' -Expected @(
    'core-local',
    'core-remote',
    'research',
    'browser'
  ) -Actual (@($Profiles.mcpGroups.PSObject.Properties | ForEach-Object { [string]$_.Name }))

  Assert-ExactSequence -Name 'mcpGroups.core-local' -Expected @('memory', 'sequential-thinking') -Actual $Profiles.mcpGroups.'core-local'
  Assert-ExactSequence -Name 'mcpGroups.core-remote' -Expected @('context7') -Actual $Profiles.mcpGroups.'core-remote'
  Assert-ExactSequence -Name 'mcpGroups.research' -Expected @('exa') -Actual $Profiles.mcpGroups.research
  Assert-ExactSequence -Name 'mcpGroups.browser' -Expected @('playwright') -Actual $Profiles.mcpGroups.browser

  if ($null -eq $Profiles.lspGroups.core) {
    throw "profiles.json must keep lspGroups.core"
  }

  Assert-ExactSequence -Name 'lspGroups.core' -Expected @('typescript', 'python') -Actual $Profiles.lspGroups.core
}

function Test-StableLspConfig {
  param(
    [Parameter(Mandatory)]
    $Lsp
  )

  Assert-ExactSet -Name 'lsp-config.json lspServers' -Expected @(
    'typescript',
    'python'
  ) -Actual (@($Lsp.lspServers.PSObject.Properties | ForEach-Object { [string]$_.Name }))
}

$settings = Get-Content (Join-Path $repoRoot 'settings.json') -Raw | ConvertFrom-Json
$profiles = Get-Content (Join-Path $repoRoot 'profiles.json') -Raw | ConvertFrom-Json
$lsp = Get-Content (Join-Path $repoRoot 'lsp-config.json') -Raw | ConvertFrom-Json

$settingsWithModel = Get-JsonClone $settings
$settingsWithModel | Add-Member -NotePropertyName 'model' -NotePropertyValue 'gpt-5'
Assert-Rejects 'settings top-level noise key' { Test-StableSettings $settingsWithModel }

$settingsWithExtraHookKey = Get-JsonClone $settings
$settingsWithExtraHookKey.hooks | Add-Member -NotePropertyName 'sessionResume' -NotePropertyValue @()
Assert-Rejects 'settings extra hook key' { Test-StableSettings $settingsWithExtraHookKey }

$settingsWithWrongHookTimeout = Get-JsonClone $settings
$settingsWithWrongHookTimeout.hooks.sessionStart[0].timeoutSec = 10
Assert-Rejects 'settings hook timeout drift' { Test-StableSettings $settingsWithWrongHookTimeout }

$settingsWithDuplicateSessionStartHook = Get-JsonClone $settings
$settingsWithDuplicateSessionStartHook.hooks.sessionStart += (Get-JsonClone $settingsWithDuplicateSessionStartHook.hooks.sessionStart[0])
Assert-Rejects 'duplicate sessionStart hook entry' { Test-StableSettings $settingsWithDuplicateSessionStartHook }

$settingsWithDuplicateSessionEndHook = Get-JsonClone $settings
$settingsWithDuplicateSessionEndHook.hooks.sessionEnd += (Get-JsonClone $settingsWithDuplicateSessionEndHook.hooks.sessionEnd[0])
Assert-Rejects 'duplicate sessionEnd hook entry' { Test-StableSettings $settingsWithDuplicateSessionEndHook }

$profilesWithWrongDefaultMcpGroups = Get-JsonClone $profiles
$profilesWithWrongDefaultMcpGroups.profiles.default.mcpGroups = @('core-local')
Assert-Rejects 'default profile mcpGroups drift' { Test-StableProfiles $profilesWithWrongDefaultMcpGroups }

$profilesWithExtraTopLevelKey = Get-JsonClone $profiles
$profilesWithExtraTopLevelKey | Add-Member -NotePropertyName 'extraTopLevel' -NotePropertyValue ([pscustomobject]@{})
Assert-Rejects 'profiles top-level noise key' { Test-StableProfiles $profilesWithExtraTopLevelKey }

$profilesWithExtraProfile = Get-JsonClone $profiles
$profilesWithExtraProfile.profiles | Add-Member -NotePropertyName 'experimental' -NotePropertyValue ([pscustomobject]@{
  description = 'noise'
  mcpGroups = @('core-local')
  lspGroups = @('core')
})
Assert-Rejects 'extra profile definition' { Test-StableProfiles $profilesWithExtraProfile }

$profilesWithWrongGroupDefinition = Get-JsonClone $profiles
$profilesWithWrongGroupDefinition.mcpGroups.'core-remote' = @('context7', 'exa')
Assert-Rejects 'mcp group definition drift' { Test-StableProfiles $profilesWithWrongGroupDefinition }

$lspWithExtraServer = Get-JsonClone $lsp
$lspWithExtraServer.lspServers | Add-Member -NotePropertyName 'php' -NotePropertyValue ([pscustomobject]@{
  command = 'phpactor'
  args = @('--stdio')
  fileExtensions = [pscustomobject]@{
    '.php' = 'php'
  }
})
Assert-Rejects 'extra lsp server definition' { Test-StableLspConfig $lspWithExtraServer }

Test-StableSettings $settings
Test-StableProfiles $profiles
Test-StableLspConfig $lsp

Write-Host 'check-stable-config smoke PASS'
