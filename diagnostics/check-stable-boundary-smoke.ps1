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

  # Ensure the path exists first - existence is required for this smoke test
  if (-not (Test-Path $Path)) {
    throw "Expected '$Path' to exist"
  }

  # git check-ignore returns 0 if ignored, 1 if not ignored, 128 on error
  $null = & git check-ignore --quiet $Path
  if ($LASTEXITCODE -eq 0) {
    throw "Expected '$Path' to not be ignored"
  } elseif ($LASTEXITCODE -eq 128) {
    throw "git check-ignore failed for '$Path' (exit code 128)"
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
