$ErrorActionPreference = 'Stop'

function Assert-Ignored {
  param(
    [string]$Path
  )

  $null = & git check-ignore $Path
  if ($LASTEXITCODE -ne 0) {
    throw "Expected '$Path' to be ignored"
  }
}

function Assert-NotIgnored {
  param(
    [string]$Path
  )

  $null = & git check-ignore $Path
  if ($LASTEXITCODE -eq 0) {
    throw "Expected '$Path' to stay tracked"
  }
}

Set-Location (Split-Path $PSScriptRoot -Parent)

Assert-Ignored 'hook-metrics.jsonl'
Assert-Ignored 'startup-metrics.jsonl'
Assert-Ignored 'mcp-health.json'
Assert-Ignored 'permissions-config.json'
Assert-NotIgnored 'profiles.json'
Assert-NotIgnored 'docs/superpowers/specs/2026-04-29-copilot-cli-stabilization-design.md'

Write-Host 'check-stable-boundary smoke PASS'
