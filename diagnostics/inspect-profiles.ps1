param(
  [string]$ProfilesPath,
  [string]$LocalMcpPath,
  [string]$RemoteMcpPath,
  [string]$LspPath
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path $PSScriptRoot -Parent

if ([string]::IsNullOrWhiteSpace($ProfilesPath)) {
  $ProfilesPath = Join-Path $scriptRoot 'profiles.json'
}
if ([string]::IsNullOrWhiteSpace($LocalMcpPath)) {
  $LocalMcpPath = Join-Path $scriptRoot 'mcp-config.json'
}
if ([string]::IsNullOrWhiteSpace($RemoteMcpPath)) {
  $RemoteMcpPath = Join-Path $scriptRoot 'mcp-config.remote.json'
}
if ([string]::IsNullOrWhiteSpace($LspPath)) {
  $LspPath = Join-Path $scriptRoot 'lsp-config.json'
}

function Read-JsonFile {
  param([string]$Path)

  if (-not (Test-Path $Path)) {
    throw "Missing file: $Path"
  }

  Get-Content -Path $Path -Raw | ConvertFrom-Json -AsHashtable
}

function Get-PropertyValue {
  param(
    $Object,
    [string]$Name
  )

  if ($null -eq $Object) {
    return $null
  }

  if ($Object -is [System.Collections.IDictionary]) {
    return ,$Object[$Name]
  }

  return ,$Object.$Name
}

function Test-HasProperty {
  param(
    $Object,
    [string]$Name
  )

  if ($null -eq $Object) {
    return $false
  }

  if ($Object -is [System.Collections.IDictionary]) {
    return $Object.Contains($Name)
  }

  return $Object.PSObject.Properties.Match($Name).Count -gt 0
}

function Get-PropertyNames {
  param($Object)

  if ($null -eq $Object) {
    return @()
  }

  if ($Object -is [System.Collections.IDictionary]) {
    return @($Object.Keys)
  }

  return @($Object.PSObject.Properties.Name)
}

function Test-IsJsonObject {
  param($Value)

  return $null -ne $Value -and ($Value -is [pscustomobject] -or $Value -is [System.Collections.IDictionary])
}

function Test-IsJsonArray {
  param($Value)

  return $null -ne $Value -and $Value -is [System.Collections.IList] -and -not ($Value -is [string])
}

function Test-IsStringArray {
  param($Value)

  if (-not (Test-IsJsonArray -Value $Value)) {
    return $false
  }

  foreach ($item in @($Value)) {
    if (-not ($item -is [string])) {
      return $false
    }
  }

  return $true
}

$profiles = Read-JsonFile -Path $ProfilesPath
$localMcp = Read-JsonFile -Path $LocalMcpPath
$remoteMcp = Read-JsonFile -Path $RemoteMcpPath
$lsp = Read-JsonFile -Path $LspPath

$errors = New-Object System.Collections.Generic.List[object]

function Add-ValidationError {
  param(
    [string]$Path,
    [string]$Code,
    [string]$Message
  )

  $errors.Add([pscustomobject]@{
      path = $Path
      code = $Code
      message = $Message
    })
}

function Get-RequiredStringArray {
  param(
    $Object,
    [string]$PropertyName,
    [string]$Path
  )

  if (-not (Test-HasProperty -Object $Object -Name $PropertyName)) {
    Add-ValidationError -Path $Path -Code 'missing-property' -Message "$Path is required"
    return $null
  }

  $value = Get-PropertyValue -Object $Object -Name $PropertyName
  if (-not (Test-IsStringArray -Value $value)) {
    Add-ValidationError -Path $Path -Code 'invalid-type' -Message "$Path must be an array of strings"
    return $null
  }

  return ,@($value)
}

$profilesRoot = Get-PropertyValue -Object $profiles -Name 'profiles'
$mcpGroupsRoot = Get-PropertyValue -Object $profiles -Name 'mcpGroups'
$lspGroupsRoot = Get-PropertyValue -Object $profiles -Name 'lspGroups'
$localMcpServers = Get-PropertyValue -Object $localMcp -Name 'mcpServers'
$remoteMcpServers = Get-PropertyValue -Object $remoteMcp -Name 'mcpServers'
$lspServers = Get-PropertyValue -Object $lsp -Name 'lspServers'

if (-not (Test-HasProperty -Object $profiles -Name 'profiles')) {
  Add-ValidationError -Path 'profiles.profiles' -Code 'missing-property' -Message 'profiles.profiles is required'
  $profilesRoot = $null
}
elseif (-not (Test-IsJsonObject -Value $profilesRoot)) {
  Add-ValidationError -Path 'profiles.profiles' -Code 'invalid-type' -Message 'profiles.profiles must be an object'
  $profilesRoot = $null
}

if (-not (Test-HasProperty -Object $profiles -Name 'mcpGroups')) {
  Add-ValidationError -Path 'profiles.mcpGroups' -Code 'missing-property' -Message 'profiles.mcpGroups is required'
  $mcpGroupsRoot = $null
}
elseif (-not (Test-IsJsonObject -Value $mcpGroupsRoot)) {
  Add-ValidationError -Path 'profiles.mcpGroups' -Code 'invalid-type' -Message 'profiles.mcpGroups must be an object'
  $mcpGroupsRoot = $null
}

if (-not (Test-HasProperty -Object $profiles -Name 'lspGroups')) {
  Add-ValidationError -Path 'profiles.lspGroups' -Code 'missing-property' -Message 'profiles.lspGroups is required'
  $lspGroupsRoot = $null
}
elseif (-not (Test-IsJsonObject -Value $lspGroupsRoot)) {
  Add-ValidationError -Path 'profiles.lspGroups' -Code 'invalid-type' -Message 'profiles.lspGroups must be an object'
  $lspGroupsRoot = $null
}

if (-not (Test-HasProperty -Object $localMcp -Name 'mcpServers')) {
  Add-ValidationError -Path 'localMcp.mcpServers' -Code 'missing-property' -Message 'localMcp.mcpServers is required'
  $localMcpServers = $null
}
elseif (-not (Test-IsJsonObject -Value $localMcpServers)) {
  Add-ValidationError -Path 'localMcp.mcpServers' -Code 'invalid-type' -Message 'localMcp.mcpServers must be an object'
  $localMcpServers = $null
}

if (-not (Test-HasProperty -Object $remoteMcp -Name 'mcpServers')) {
  Add-ValidationError -Path 'remoteMcp.mcpServers' -Code 'missing-property' -Message 'remoteMcp.mcpServers is required'
  $remoteMcpServers = $null
}
elseif (-not (Test-IsJsonObject -Value $remoteMcpServers)) {
  Add-ValidationError -Path 'remoteMcp.mcpServers' -Code 'invalid-type' -Message 'remoteMcp.mcpServers must be an object'
  $remoteMcpServers = $null
}

if (-not (Test-HasProperty -Object $lsp -Name 'lspServers')) {
  Add-ValidationError -Path 'lsp.lspServers' -Code 'missing-property' -Message 'lsp.lspServers is required'
  $lspServers = $null
}
elseif (-not (Test-IsJsonObject -Value $lspServers)) {
  Add-ValidationError -Path 'lsp.lspServers' -Code 'invalid-type' -Message 'lsp.lspServers must be an object'
  $lspServers = $null
}

$knownMcpServerNames = @(Get-PropertyNames -Object $localMcpServers) + @(Get-PropertyNames -Object $remoteMcpServers)
$knownLspServerNames = @(Get-PropertyNames -Object $lspServers)
$profileNames = @(Get-PropertyNames -Object $profilesRoot)
$mcpGroupNames = @(Get-PropertyNames -Object $mcpGroupsRoot)
$lspGroupNames = @(Get-PropertyNames -Object $lspGroupsRoot)
$validMcpGroups = @{}
$validLspGroups = @{}

foreach ($groupName in $mcpGroupNames) {
  $groupPath = "profiles.mcpGroups.$groupName"
  $groupValue = Get-PropertyValue -Object $mcpGroupsRoot -Name $groupName

  if (-not (Test-IsStringArray -Value $groupValue)) {
    Add-ValidationError -Path $groupPath -Code 'invalid-type' -Message "$groupPath must be an array of strings"
    continue
  }

  $validMcpGroups[$groupName] = @($groupValue)
}

foreach ($groupName in $lspGroupNames) {
  $groupPath = "profiles.lspGroups.$groupName"
  $groupValue = Get-PropertyValue -Object $lspGroupsRoot -Name $groupName

  if (-not (Test-IsStringArray -Value $groupValue)) {
    Add-ValidationError -Path $groupPath -Code 'invalid-type' -Message "$groupPath must be an array of strings"
    continue
  }

  $validLspGroups[$groupName] = @($groupValue)
}

foreach ($profileName in $profileNames) {
  $profilePath = "profiles.profiles.$profileName"
  $profile = Get-PropertyValue -Object $profilesRoot -Name $profileName

  if (-not (Test-IsJsonObject -Value $profile)) {
    Add-ValidationError -Path $profilePath -Code 'invalid-type' -Message "$profilePath must be an object"
    continue
  }

  $profileMcpGroups = Get-RequiredStringArray -Object $profile -PropertyName 'mcpGroups' -Path "$profilePath.mcpGroups"
  $profileLspGroups = Get-RequiredStringArray -Object $profile -PropertyName 'lspGroups' -Path "$profilePath.lspGroups"

  if ($null -ne $profileMcpGroups -and $null -ne $mcpGroupsRoot) {
    for ($groupIndex = 0; $groupIndex -lt $profileMcpGroups.Count; $groupIndex++) {
      $groupName = $profileMcpGroups[$groupIndex]
      $groupReferencePath = "$profilePath.mcpGroups[$groupIndex]"

      if (-not $validMcpGroups.ContainsKey($groupName)) {
        if ($groupName -notin $mcpGroupNames) {
          Add-ValidationError -Path $groupReferencePath -Code 'unknown-reference' -Message "$groupReferencePath references unknown MCP group '$groupName'"
        }

        continue
      }

      $serverNames = @($validMcpGroups[$groupName])
      for ($serverIndex = 0; $serverIndex -lt $serverNames.Count; $serverIndex++) {
        $serverName = $serverNames[$serverIndex]
        $serverReferencePath = "profiles.mcpGroups.$groupName[$serverIndex]"

        if ($serverName -notin $knownMcpServerNames) {
          Add-ValidationError -Path $serverReferencePath -Code 'unknown-reference' -Message "$serverReferencePath references unknown MCP server '$serverName' for profile '$profileName'"
        }
      }
    }
  }

  if ($null -ne $profileLspGroups -and $null -ne $lspGroupsRoot) {
    for ($groupIndex = 0; $groupIndex -lt $profileLspGroups.Count; $groupIndex++) {
      $groupName = $profileLspGroups[$groupIndex]
      $groupReferencePath = "$profilePath.lspGroups[$groupIndex]"

      if (-not $validLspGroups.ContainsKey($groupName)) {
        if ($groupName -notin $lspGroupNames) {
          Add-ValidationError -Path $groupReferencePath -Code 'unknown-reference' -Message "$groupReferencePath references unknown LSP group '$groupName'"
        }

        continue
      }

      $serverNames = @($validLspGroups[$groupName])
      for ($serverIndex = 0; $serverIndex -lt $serverNames.Count; $serverIndex++) {
        $serverName = $serverNames[$serverIndex]
        $serverReferencePath = "profiles.lspGroups.$groupName[$serverIndex]"

        if ($serverName -notin $knownLspServerNames) {
          Add-ValidationError -Path $serverReferencePath -Code 'unknown-reference' -Message "$serverReferencePath references unknown LSP server '$serverName' for profile '$profileName'"
        }
      }
    }
  }
}

[ordered]@{
  profileCount = $profileNames.Count
  profileNames = $profileNames
  errorCount = $errors.Count
  errors = $errors
} | ConvertTo-Json -Depth 6 -Compress
