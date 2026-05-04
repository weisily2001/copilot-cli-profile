$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot 'check-mcp-health.ps1'

if (-not (Test-Path $scriptPath)) {
  throw "Missing script: $scriptPath"
}

function Assert-Equal {
  param(
    $Actual,
    $Expected,
    [string]$Message
  )

  if ($Actual -ne $Expected) {
    throw "$Message. Expected '$Expected', got '$Actual'"
  }
}

function Assert-NotNull {
  param(
    $Value,
    [string]$Message
  )

  if ($null -eq $Value) {
    throw $Message
  }

  if ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value)) {
    throw $Message
  }
}

function Assert-NullOrEmpty {
  param(
    $Value,
    [string]$Message
  )

  if ($null -ne $Value -and (-not ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value)))) {
    throw "$Message. Expected null or empty, got '$Value'"
  }
}

function Assert-Rejects {
  param(
    [string]$Name,
    [scriptblock]$Action
  )

  try {
    & $Action
  }
  catch {
    return
  }

  throw "Expected failure for '$Name'"
}

function Get-ResultByName {
  param(
    $Health,
    [string]$Name
  )

  $matches = @($Health.results | Where-Object { $_.name -eq $Name })
  if ($matches.Count -ne 1) {
    throw "Expected exactly one result named '$Name', got $($matches.Count)"
  }

  return $matches[0]
}

function Invoke-HealthScript {
  param(
    [string]$CandidateScriptPath,
    [switch]$UseWindowsPowerShell
  )

  if (Test-Path $outputPath) {
    Remove-Item -Path $outputPath -Force
  }

  if ($UseWindowsPowerShell) {
    $powerShellArgs = @(
      '-NoLogo',
      '-NoProfile',
      '-File', $CandidateScriptPath,
      '-LocalMcpPath', $localPath,
      '-RemoteMcpPath', $remotePath,
      '-RulesPath', $rulesPath,
      '-OutputPath', $outputPath
    )
    if ($SkipHttpProbe) {
      $powerShellArgs += '-SkipHttpProbe'
    }

    $commandOutput = & powershell @powerShellArgs 2>&1 | Out-String
    $exitCode = $LASTEXITCODE

    return [pscustomobject]@{
      exitCode = $exitCode
      output   = $commandOutput
      health   = if ($exitCode -eq 0 -and (Test-Path $outputPath)) {
        Get-Content -Path $outputPath -Raw -Encoding UTF8 | ConvertFrom-Json
      }
      else {
        $null
      }
    }
  }

  return [pscustomobject]@{
    exitCode = 0
    output   = $null
    health   = & $CandidateScriptPath `
      -LocalMcpPath $localPath `
      -RemoteMcpPath $remotePath `
      -RulesPath $rulesPath `
      -OutputPath $outputPath `
      -SkipHttpProbe:$SkipHttpProbe | ConvertFrom-Json
  }
}

function Write-Utf8NoBomFile {
  param(
    [string]$Path,
    [string]$Content
  )

  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Get-FreePort {
  $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
  $listener.Start()
  try {
    return $listener.LocalEndpoint.Port
  }
  finally {
    $listener.Stop()
  }
}

function Start-MethodAwareProbeServer {
  param([int]$Port)

  $job = Start-Job -ArgumentList $Port -ScriptBlock {
    param($Port)

    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add("http://127.0.0.1:$Port/")
    $listener.Start()

    try {
      $handled = 0
      while ($handled -lt 4) {
        $context = $listener.GetContext()
        try {
          switch ($context.Request.HttpMethod) {
            'HEAD' {
              $context.Response.StatusCode = 405
            }
            'OPTIONS' {
              $context.Response.StatusCode = 204
              $context.Response.Headers['Allow'] = 'OPTIONS'
            }
            default {
              $context.Response.StatusCode = 404
            }
          }
          $context.Response.Close()
        }
        finally {
          $handled++
        }
      }
    }
    finally {
      $listener.Stop()
      $listener.Close()
    }
  }

  for ($attempt = 0; $attempt -lt 30; $attempt++) {
    try {
      $client = [System.Net.Sockets.TcpClient]::new()
      $client.Connect('127.0.0.1', $Port)
      $client.Close()
      return $job
    }
    catch {
      Start-Sleep -Milliseconds 100
    }
  }

  Stop-Job -Job $job | Out-Null
  Receive-Job -Job $job -ErrorAction SilentlyContinue | Out-Null
  throw "Timed out waiting for probe server on port $Port"
}

function Assert-SkipProbeBehavior {
  param($Health)

  Assert-NotNull -Value $Health.generatedAt -Message 'Missing generatedAt'

  $localGood = Get-ResultByName -Health $Health -Name 'local-good'
  Assert-Equal -Actual $localGood.type -Expected 'local' -Message 'local-good type mismatch'
  Assert-Equal -Actual $localGood.status -Expected 'healthy' -Message 'local-good status mismatch'
  Assert-NullOrEmpty -Value $localGood.suggestedAction -Message 'local-good suggestedAction mismatch'
  Assert-NotNull -Value $localGood.checkedAt -Message 'Missing local-good checkedAt'

  $localMissing = Get-ResultByName -Health $health -Name 'local-missing'
  Assert-Equal -Actual $localMissing.type -Expected 'local' -Message 'local-missing type mismatch'
  Assert-Equal -Actual $localMissing.status -Expected 'unavailable' -Message 'local-missing status mismatch'
  Assert-Equal -Actual $localMissing.suggestedAction -Expected 'repair missing local command' -Message 'local-missing suggestedAction mismatch'
  Assert-NotNull -Value $localMissing.error -Message 'Missing local-missing error'
  Assert-NotNull -Value $localMissing.checkedAt -Message 'Missing local-missing checkedAt'

  $remoteSkip = Get-ResultByName -Health $health -Name 'remote-skip'
  Assert-Equal -Actual $remoteSkip.type -Expected 'remote' -Message 'remote-skip type mismatch'
  Assert-Equal -Actual $remoteSkip.status -Expected 'degraded' -Message 'remote-skip status mismatch'
  Assert-Equal -Actual $remoteSkip.suggestedAction -Expected 'defer remote probe for smoke' -Message 'remote-skip suggestedAction mismatch'
  Assert-NotNull -Value $remoteSkip.checkedAt -Message 'Missing remote-skip checkedAt'

  if (-not (Test-Path $outputPath)) {
    throw "Expected output file: $outputPath"
  }

  $saved = Get-Content -Path $outputPath -Raw -Encoding UTF8 | ConvertFrom-Json
  Assert-NotNull -Value $saved.generatedAt -Message 'Missing saved generatedAt'
  if (@($saved.results).Count -ne 3) {
    throw "Expected 3 saved results, got $(@($saved.results).Count)"
  }
}

function Assert-RemoteReachableDespiteMethod405 {
  param($Health)

  $remote = Get-ResultByName -Health $Health -Name 'remote-405'
  Assert-Equal -Actual $remote.type -Expected 'remote' -Message 'remote-405 type mismatch'
  Assert-Equal -Actual $remote.status -Expected 'healthy' -Message 'remote-405 status mismatch'
  Assert-NullOrEmpty -Value $remote.error -Message 'remote-405 error mismatch'
  Assert-NullOrEmpty -Value $remote.suggestedAction -Message 'remote-405 suggestedAction mismatch'
  Assert-NotNull -Value $remote.checkedAt -Message 'Missing remote-405 checkedAt'
}

function Assert-WindowsPowerShellUtf8RulesSupport {
  param($Invocation)

  if ($Invocation.exitCode -ne 0) {
    throw "Expected Windows PowerShell run to succeed, got exit code $($Invocation.exitCode): $($Invocation.output)"
  }

  if ($null -eq $Invocation.health) {
    throw 'Expected Windows PowerShell run to write health output'
  }

  $localGood = Get-ResultByName -Health $Invocation.health -Name 'local-good'
  Assert-Equal -Actual $localGood.status -Expected 'healthy' -Message 'Windows PowerShell local-good status mismatch'

  $localMissing = Get-ResultByName -Health $Invocation.health -Name 'local-missing'
  Assert-Equal -Actual $localMissing.suggestedAction -Expected '修复缺失命令' -Message 'Windows PowerShell suggestedAction mismatch'
}

$legacyFixtureRoot = Join-Path $PSScriptRoot '_check-mcp-health-smoke'
$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("check-mcp-health-smoke-" + [guid]::NewGuid().ToString('N'))
$fixtureDiag = Join-Path $fixtureRoot 'diagnostics'
$localPath = Join-Path $fixtureRoot 'mcp-config.json'
$remotePath = Join-Path $fixtureRoot 'mcp-config.remote.json'
$rulesPath = Join-Path $fixtureRoot 'mcp-health-rules.json'
$outputPath = Join-Path $fixtureRoot 'mcp-health.json'
$candidateScriptPath = Join-Path $fixtureDiag 'check-mcp-health.ps1'
$brokenProbeScriptPath = Join-Path $fixtureDiag 'broken-head-check-mcp-health.ps1'
$brokenEncodingScriptPath = Join-Path $fixtureDiag 'broken-encoding-check-mcp-health.ps1'
$SkipHttpProbe = $false

if (Test-Path $legacyFixtureRoot) {
  Remove-Item -Path $legacyFixtureRoot -Recurse -Force
}

if (Test-Path $fixtureRoot) {
  Remove-Item -Path $fixtureRoot -Recurse -Force
}

New-Item -ItemType Directory -Path $fixtureDiag -Force | Out-Null

try {
  $sourceScript = Get-Content -Path $scriptPath -Raw
  $brokenProbeScript = $sourceScript.Replace(
    '$null = Invoke-WebRequest -Uri $url -Method Options -UseBasicParsing -TimeoutSec 10',
    '$null = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -TimeoutSec 10'
  )
  if ($brokenProbeScript -eq $sourceScript) {
    throw 'Failed to inject broken HTTP probe method behavior'
  }

  $brokenEncodingScript = $sourceScript.Replace(
    '  Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json',
    '  Get-Content -Path $Path -Raw | ConvertFrom-Json'
  )
  if ($brokenEncodingScript -eq $sourceScript) {
    throw 'Failed to inject broken UTF-8 rules loading behavior'
  }

  $sourceScript | Set-Content -Path $candidateScriptPath -Encoding UTF8
  $brokenProbeScript | Set-Content -Path $brokenProbeScriptPath -Encoding UTF8
  $brokenEncodingScript | Set-Content -Path $brokenEncodingScriptPath -Encoding UTF8

  $SkipHttpProbe = $true
  @'
{
  "mcpServers": {
    "local-good": {
      "type": "local",
      "command": "powershell"
    },
    "local-missing": {
      "type": "local",
      "command": "command-that-should-not-exist-12345"
    }
  }
}
'@ | Set-Content -Path $localPath -Encoding UTF8

  @'
{
  "mcpServers": {
    "remote-skip": {
      "type": "http",
      "url": "https://example.invalid/mcp"
    }
  }
}
'@ | Set-Content -Path $remotePath -Encoding UTF8

  @'
{
  "defaults": {
    "localMissingAction": "install local dependency",
    "remoteSkippedAction": "enable probe later",
    "remoteFailedAction": "check remote service"
  },
  "overrides": {
    "context7": {
      "suggestedAction": "use docs fallback"
    },
    "exa": {
      "suggestedAction": "disable research enhancement"
    },
    "local-missing": {
      "suggestedAction": "repair missing local command"
    },
    "remote-skip": {
      "suggestedAction": "defer remote probe for smoke"
    }
  }
}
'@ | Set-Content -Path $rulesPath -Encoding UTF8

  $skipProbeInvocation = Invoke-HealthScript -CandidateScriptPath $candidateScriptPath
  Assert-SkipProbeBehavior -Health $skipProbeInvocation.health

  $SkipHttpProbe = $false
  $port = Get-FreePort
  $probeJob = Start-MethodAwareProbeServer -Port $port
  try {
    '{"mcpServers":{"local-good":{"type":"local","command":"powershell"}}}' | Set-Content -Path $localPath -Encoding UTF8
    "{""mcpServers"":{""remote-405"":{""type"":""http"",""url"":""http://127.0.0.1:$port/""}}}" | Set-Content -Path $remotePath -Encoding UTF8
    '{"defaults":{"localMissingAction":"install local dependency","remoteSkippedAction":"enable probe later","remoteFailedAction":"check remote service"}}' | Set-Content -Path $rulesPath -Encoding UTF8

    $brokenProbeInvocation = Invoke-HealthScript -CandidateScriptPath $brokenProbeScriptPath
    $brokenProbeResult = Get-ResultByName -Health $brokenProbeInvocation.health -Name 'remote-405'
    Assert-Equal -Actual $brokenProbeResult.status -Expected 'unavailable' -Message 'broken remote-405 status mismatch'
    Assert-Rejects -Name '405 reachability regression' {
      Assert-RemoteReachableDespiteMethod405 -Health $brokenProbeInvocation.health
    }

    $probeInvocation = Invoke-HealthScript -CandidateScriptPath $candidateScriptPath
    Assert-RemoteReachableDespiteMethod405 -Health $probeInvocation.health
  }
  finally {
    Stop-Job -Job $probeJob | Out-Null
    Receive-Job -Job $probeJob -ErrorAction SilentlyContinue | Out-Null
  }

  $SkipHttpProbe = $true
  @'
{
  "mcpServers": {
    "local-good": {
      "type": "local",
      "command": "powershell"
    },
    "local-missing": {
      "type": "local",
      "command": "command-that-should-not-exist-12345"
    }
  }
}
'@ | Set-Content -Path $localPath -Encoding UTF8
  '{"mcpServers":{}}' | Set-Content -Path $remotePath -Encoding UTF8
  Write-Utf8NoBomFile -Path $rulesPath -Content @'
{
  "defaults": {
    "localMissingAction": "修复本地命令或安装缺失依赖",
    "remoteSkippedAction": "启用联网探测或回退到本地文档方案",
    "remoteFailedAction": "检查网络、认证或远端服务状态"
  },
  "overrides": {
    "local-missing": {
      "suggestedAction": "修复缺失命令"
    }
  }
}
'@

  $brokenEncodingInvocation = Invoke-HealthScript -CandidateScriptPath $brokenEncodingScriptPath -UseWindowsPowerShell
  if ($brokenEncodingInvocation.exitCode -eq 0) {
    throw 'Expected broken Windows PowerShell UTF-8 regression case to fail'
  }
  if ($brokenEncodingInvocation.output -notmatch 'ConvertFrom-Json') {
    throw "Expected broken Windows PowerShell UTF-8 regression output to mention ConvertFrom-Json, got: $($brokenEncodingInvocation.output)"
  }

  $windowsPowerShellInvocation = Invoke-HealthScript -CandidateScriptPath $candidateScriptPath -UseWindowsPowerShell
  Assert-WindowsPowerShellUtf8RulesSupport -Invocation $windowsPowerShellInvocation
}
finally {
  if (Test-Path $fixtureRoot) {
    Remove-Item -Path $fixtureRoot -Recurse -Force
  }

  if (Test-Path $legacyFixtureRoot) {
    Remove-Item -Path $legacyFixtureRoot -Recurse -Force
  }
}

if (Test-Path $fixtureRoot) {
  throw "Fixture directory should be removed after smoke: $fixtureRoot"
}

if (Test-Path $legacyFixtureRoot) {
  throw "Legacy fixture directory should be removed after smoke: $legacyFixtureRoot"
}

Write-Host 'check-mcp-health smoke PASS'
