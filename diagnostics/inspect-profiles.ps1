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

  Get-Content -Path $Path -Raw | ConvertFrom-Json
}

function Get-PropertyValue {
  param(
    $Object,
    [string]$Name
  )

  if ($null -eq $Object) {
    return $null
  }

  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) {
    return $null
  }

  return $property.Value
}

function Get-PropertyNames {
  param($Object)

  if ($null -eq $Object) {
    return @()
  }

  return @($Object.PSObject.Properties.Name)
}

$profiles = Read-JsonFile -Path $ProfilesPath
$localMcp = Read-JsonFile -Path $LocalMcpPath
$remoteMcp = Read-JsonFile -Path $RemoteMcpPath
$lsp = Read-JsonFile -Path $LspPath

$errors = New-Object System.Collections.Generic.List[string]
$profilesRoot = Get-PropertyValue -Object $profiles -Name 'profiles'
$mcpGroupsRoot = Get-PropertyValue -Object $profiles -Name 'mcpGroups'
$lspGroupsRoot = Get-PropertyValue -Object $profiles -Name 'lspGroups'
$localMcpServers = Get-PropertyValue -Object $localMcp -Name 'mcpServers'
$remoteMcpServers = Get-PropertyValue -Object $remoteMcp -Name 'mcpServers'
$lspServers = Get-PropertyValue -Object $lsp -Name 'lspServers'
$profileNames = Get-PropertyNames -Object $profilesRoot
$lspServerNames = Get-PropertyNames -Object $lspServers
$knownMcpServerNames = @(Get-PropertyNames -Object $localMcpServers) + @(Get-PropertyNames -Object $remoteMcpServers)

if ($null -eq $profilesRoot) {
  $errors.Add('Missing profiles.profiles')
}
if ($null -eq $mcpGroupsRoot) {
  $errors.Add('Missing profiles.mcpGroups')
}
if ($null -eq $lspGroupsRoot) {
  $errors.Add('Missing profiles.lspGroups')
}
if ($null -eq $localMcpServers) {
  $errors.Add('Missing local mcpServers')
}
if ($null -eq $remoteMcpServers) {
  $errors.Add('Missing remote mcpServers')
}
if ($null -eq $lspServers) {
  $errors.Add('Missing lspServers')
}

foreach ($profileName in $profileNames) {
  $profile = Get-PropertyValue -Object $profilesRoot -Name $profileName
  $profileMcpGroups = Get-PropertyValue -Object $profile -Name 'mcpGroups'
  $profileLspGroups = Get-PropertyValue -Object $profile -Name 'lspGroups'

  if ($null -eq $profileMcpGroups) {
    $errors.Add("Profile '$profileName' is missing mcpGroups")
  }
  if ($null -eq $profileLspGroups) {
    $errors.Add("Profile '$profileName' is missing lspGroups")
  }

  foreach ($groupName in @($profileMcpGroups)) {
    if ($null -eq $mcpGroupsRoot) {
      continue
    }

    if (-not (Get-PropertyNames -Object $mcpGroupsRoot).Contains($groupName)) {
      $errors.Add("Unknown MCP group '$groupName' in profile '$profileName'")
      continue
    }

    foreach ($serverName in @(Get-PropertyValue -Object $mcpGroupsRoot -Name $groupName)) {
      if (-not $knownMcpServerNames.Contains($serverName)) {
        $errors.Add("Unknown MCP server '$serverName' in group '$groupName' for profile '$profileName'")
      }
    }
  }

  foreach ($groupName in @($profileLspGroups)) {
    if ($null -eq $lspGroupsRoot) {
      continue
    }

    if (-not (Get-PropertyNames -Object $lspGroupsRoot).Contains($groupName)) {
      $errors.Add("Unknown LSP group '$groupName' in profile '$profileName'")
      continue
    }

    foreach ($serverName in @(Get-PropertyValue -Object $lspGroupsRoot -Name $groupName)) {
      if (-not $lspServerNames.Contains($serverName)) {
        $errors.Add("Unknown LSP server '$serverName' in group '$groupName' for profile '$profileName'")
      }
    }
  }
}

[ordered]@{
  profileCount = $profileNames.Count
  profileNames = $profileNames
  errorCount = $errors.Count
  errors = $errors
} | ConvertTo-Json -Depth 5 -Compress
