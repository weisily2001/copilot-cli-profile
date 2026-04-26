param()

$ErrorActionPreference = 'Stop'
$configPath = Join-Path $HOME '.copilot\config.json'

if (-not (Test-Path $configPath)) {
  throw "Missing config.json: $configPath"
}

function Convert-ConfigJson {
  param([string]$Path)

  $raw = Get-Content -Path $Path -Raw
  $json = ($raw -split "\r?\n" | Where-Object { $_ -notmatch '^\s*//' }) -join [Environment]::NewLine
  return $json | ConvertFrom-Json
}

$config = Convert-ConfigJson -Path $configPath
$lastLoggedInUser = $config.lastLoggedInUser
$lastLoginUser = if ($null -ne $lastLoggedInUser -and -not [string]::IsNullOrWhiteSpace([string]$lastLoggedInUser.login)) { [string]$lastLoggedInUser.login } else { $null }
$lastLoginHost = if ($null -ne $lastLoggedInUser -and -not [string]::IsNullOrWhiteSpace([string]$lastLoggedInUser.host)) { [string]$lastLoggedInUser.host } else { $null }
$trustedFolders = [int]@($config.trustedFolders).Count

[ordered]@{
  configPath      = $configPath
  hasCachedLogin  = $null -ne $lastLoggedInUser
  lastLoginHost   = $lastLoginHost
  lastLoginUser   = $lastLoginUser
  trustedFolders  = $trustedFolders
} | ConvertTo-Json -Depth 3 -Compress
