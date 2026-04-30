param(
  [string]$LocalMcpPath,
  [string]$RemoteMcpPath,
  [string]$RulesPath,
  [string]$OutputPath,
  [switch]$SkipHttpProbe
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent

if ([string]::IsNullOrWhiteSpace($LocalMcpPath)) {
  $LocalMcpPath = Join-Path $repoRoot 'mcp-config.json'
}
if ([string]::IsNullOrWhiteSpace($RemoteMcpPath)) {
  $RemoteMcpPath = Join-Path $repoRoot 'mcp-config.remote.json'
}
if ([string]::IsNullOrWhiteSpace($RulesPath)) {
  $RulesPath = Join-Path $repoRoot 'mcp-health-rules.json'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $repoRoot 'mcp-health.json'
}

function Read-JsonFile {
  param([string]$Path)

  if (-not (Test-Path $Path)) {
    throw "Missing file: $Path"
  }

  Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
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

function Get-StringValue {
  param(
    $Object,
    [string]$Name
  )

  $value = Get-PropertyValue -Object $Object -Name $Name
  if ($value -is [string] -and -not [string]::IsNullOrWhiteSpace($value)) {
    return $value
  }

  return $null
}

function Get-SuggestedAction {
  param(
    [string]$Name,
    [string]$Status,
    [string]$ServerKind,
    $Rules
  )

  $overrides = Get-PropertyValue -Object $Rules -Name 'overrides'
  $override = Get-PropertyValue -Object $overrides -Name $Name
  $overrideAction = Get-StringValue -Object $override -Name 'suggestedAction'
  if (-not [string]::IsNullOrWhiteSpace($overrideAction) -and $Status -ne 'healthy') {
    return $overrideAction
  }

  $defaults = Get-PropertyValue -Object $Rules -Name 'defaults'
  if ($ServerKind -eq 'local' -and $Status -eq 'unavailable') {
    return Get-StringValue -Object $defaults -Name 'localMissingAction'
  }

  if ($ServerKind -eq 'remote' -and $Status -eq 'degraded') {
    return Get-StringValue -Object $defaults -Name 'remoteSkippedAction'
  }

  if ($ServerKind -eq 'remote' -and $Status -eq 'unavailable') {
    return Get-StringValue -Object $defaults -Name 'remoteFailedAction'
  }

  return $null
}

function New-HealthResult {
  param(
    [string]$Name,
    [string]$Type,
    [string]$Status,
    [long]$LatencyMs,
    [string]$CheckedAt,
    [string]$Error,
    [string]$SuggestedAction
  )

  [pscustomobject][ordered]@{
    name            = $Name
    type            = $Type
    status          = $Status
    latencyMs       = $LatencyMs
    checkedAt       = $CheckedAt
    error           = $Error
    suggestedAction = $SuggestedAction
  }
}

function Test-LocalCommand {
  param(
    [string]$Name,
    $Server,
    $Rules
  )

  $checkedAt = (Get-Date).ToString('o')
  $commandName = Get-StringValue -Object $Server -Name 'command'
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $command = $null
  if (-not [string]::IsNullOrWhiteSpace($commandName)) {
    $command = Get-Command -Name $commandName -ErrorAction SilentlyContinue
  }
  $sw.Stop()

  if ($null -ne $command) {
    return New-HealthResult -Name $Name -Type 'local' -Status 'healthy' -LatencyMs $sw.ElapsedMilliseconds -CheckedAt $checkedAt -Error $null -SuggestedAction $null
  }

  $errorMessage = if ([string]::IsNullOrWhiteSpace($commandName)) {
    "Local MCP server '$Name' is missing command"
  }
  else {
    "Local MCP command '$commandName' was not found"
  }

  return New-HealthResult -Name $Name -Type 'local' -Status 'unavailable' -LatencyMs $sw.ElapsedMilliseconds -CheckedAt $checkedAt -Error $errorMessage -SuggestedAction (Get-SuggestedAction -Name $Name -Status 'unavailable' -ServerKind 'local' -Rules $Rules)
}

function Test-RemoteEndpoint {
  param(
    [string]$Name,
    $Server,
    $Rules,
    [bool]$SkipProbe
  )

  $checkedAt = (Get-Date).ToString('o')
  $url = Get-StringValue -Object $Server -Name 'url'
  if ($SkipProbe) {
    return New-HealthResult -Name $Name -Type 'remote' -Status 'degraded' -LatencyMs 0 -CheckedAt $checkedAt -Error 'HTTP probe skipped' -SuggestedAction (Get-SuggestedAction -Name $Name -Status 'degraded' -ServerKind 'remote' -Rules $Rules)
  }

  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  try {
    if ([string]::IsNullOrWhiteSpace($url)) {
      throw "Remote MCP server '$Name' is missing url"
    }

    $null = Invoke-WebRequest -Uri $url -Method Options -UseBasicParsing -TimeoutSec 10
    $sw.Stop()
    return New-HealthResult -Name $Name -Type 'remote' -Status 'healthy' -LatencyMs $sw.ElapsedMilliseconds -CheckedAt $checkedAt -Error $null -SuggestedAction $null
  }
  catch {
    $sw.Stop()
    return New-HealthResult -Name $Name -Type 'remote' -Status 'unavailable' -LatencyMs $sw.ElapsedMilliseconds -CheckedAt $checkedAt -Error $_.Exception.Message -SuggestedAction (Get-SuggestedAction -Name $Name -Status 'unavailable' -ServerKind 'remote' -Rules $Rules)
  }
}

$localMcp = Read-JsonFile -Path $LocalMcpPath
$remoteMcp = Read-JsonFile -Path $RemoteMcpPath
$rules = Read-JsonFile -Path $RulesPath

$results = @()
$localServers = Get-PropertyValue -Object $localMcp -Name 'mcpServers'
$remoteServers = Get-PropertyValue -Object $remoteMcp -Name 'mcpServers'

foreach ($name in @(Get-PropertyNames -Object $localServers)) {
  $server = Get-PropertyValue -Object $localServers -Name $name
  $results += Test-LocalCommand -Name $name -Server $server -Rules $rules
}

foreach ($name in @(Get-PropertyNames -Object $remoteServers)) {
  $server = Get-PropertyValue -Object $remoteServers -Name $name
  $results += Test-RemoteEndpoint -Name $name -Server $server -Rules $rules -SkipProbe $SkipHttpProbe.IsPresent
}

$health = [pscustomobject][ordered]@{
  generatedAt = (Get-Date).ToString('o')
  results     = @($results)
}

$outputDir = Split-Path -Path $OutputPath -Parent
if (-not [string]::IsNullOrWhiteSpace($outputDir) -and -not (Test-Path $outputDir)) {
  New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$json = $health | ConvertTo-Json -Depth 6
$json | Set-Content -Path $OutputPath -Encoding UTF8
$json
