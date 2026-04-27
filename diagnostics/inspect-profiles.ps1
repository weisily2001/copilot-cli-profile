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

$profiles = Read-JsonFile -Path $ProfilesPath
$localMcp = Read-JsonFile -Path $LocalMcpPath
$remoteMcp = Read-JsonFile -Path $RemoteMcpPath
$lsp = Read-JsonFile -Path $LspPath

$errors = New-Object System.Collections.Generic.List[string]
$profileNames = @($profiles.profiles.PSObject.Properties.Name)

if ($null -eq $localMcp.mcpServers) {
  $errors.Add('Missing local mcpServers')
}
if ($null -eq $remoteMcp.mcpServers) {
  $errors.Add('Missing remote mcpServers')
}
if ($null -eq $lsp.lspServers) {
  $errors.Add('Missing lspServers')
}

foreach ($profileName in $profileNames) {
  $profile = $profiles.profiles.$profileName

  foreach ($groupName in @($profile.mcpGroups)) {
    if (-not $profiles.mcpGroups.PSObject.Properties.Name.Contains($groupName)) {
      $errors.Add("Unknown MCP group '$groupName' in profile '$profileName'")
    }
  }

  foreach ($groupName in @($profile.lspGroups)) {
    if (-not $profiles.lspGroups.PSObject.Properties.Name.Contains($groupName)) {
      $errors.Add("Unknown LSP group '$groupName' in profile '$profileName'")
    }
  }
}

[ordered]@{
  profileCount = $profileNames.Count
  profileNames = $profileNames
  errorCount = $errors.Count
  errors = $errors
} | ConvertTo-Json -Depth 5 -Compress
