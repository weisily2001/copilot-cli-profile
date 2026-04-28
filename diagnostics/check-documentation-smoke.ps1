$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
$readmePath = Join-Path $repoRoot 'README.md'
$startupPath = Join-Path $repoRoot 'startup-observability.md'
$mcpObservabilityPath = Join-Path $repoRoot 'mcp-observability.md'

function Read-Utf8File {
  param(
    [string]$Path
  )

  if (-not (Test-Path $Path)) {
    throw "Missing file: $Path"
  }

  # Use .NET to read UTF8 exactly the same under Windows PowerShell and PowerShell Core
  return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Assert-ContainsLiteral {
  param(
    [string]$Content,
    [string]$Literal,
    [string]$Context
  )

  # Normalize: remove Markdown inline code backticks and compare ordinally
  $normLiteral = $Literal -replace '`',''
  $normContent = $Content -replace '`',''

  if ($null -eq $normContent -or $normContent.IndexOf($normLiteral, [System.StringComparison]::Ordinal) -lt 0) {
    throw "$Context missing '$Literal'"
  }
}

$readme = Read-Utf8File -Path $readmePath
$startup = Read-Utf8File -Path $startupPath
$mcpObservability = Read-Utf8File -Path $mcpObservabilityPath

Assert-ContainsLiteral -Content $readme -Literal 'profiles.json' -Context 'README.md'
Assert-ContainsLiteral -Content $readme -Literal 'check-mcp-health.ps1' -Context 'README.md'
Assert-ContainsLiteral -Content $readme -Literal '默认写入当前仓库根目录下的 `mcp-health.json`' -Context 'README.md'
Assert-ContainsLiteral -Content $startup -Literal 'mcp-observability.md' -Context 'startup-observability.md'
Assert-ContainsLiteral -Content $mcpObservability -Literal '默认写入当前仓库根目录下的 `mcp-health.json`' -Context 'mcp-observability.md'

Write-Host 'documentation smoke PASS'
