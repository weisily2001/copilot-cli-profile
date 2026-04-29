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

function Assert-PathExists {
  param(
    [string]$Path
  )

  if (-not (Test-Path $Path)) {
    throw "Expected existing path '$Path' to exist"
  }
}

function Assert-ExistingPathNotIgnored {
  param(
    [string]$Path
  )

  # Ensure the path exists first - existence is required for this smoke test
  Assert-PathExists $Path

  # Verify path pattern is not ignored by .gitignore (use --no-index to evaluate patterns)
  $null = & git check-ignore --quiet --no-index $Path 2>$null
  if ($LASTEXITCODE -eq 0) {
    throw "Expected existing path '$Path' to not be ignored by .gitignore"
  } elseif ($LASTEXITCODE -eq 128) {
    throw "git check-ignore failed for '$Path' (exit code 128)"
  }
}

function Assert-PathPatternNotIgnored {
  param(
    [string]$Path
  )

  # Do NOT require the path to exist. This assertion only checks whether the path name or pattern
  # would be ignored by .gitignore rules.
  # git check-ignore returns 0 if ignored, 1 if not ignored, 128 on error
  $null = & git check-ignore --quiet --no-index $Path 2>$null
  if ($LASTEXITCODE -eq 0) {
    throw "Expected path name/pattern '$Path' to not be ignored by .gitignore"
  } elseif ($LASTEXITCODE -eq 128) {
    throw "git check-ignore failed for '$Path' (exit code 128)"
  }
}

Set-Location (Split-Path $PSScriptRoot -Parent)

Assert-Ignored 'hook-metrics.jsonl'
Assert-Ignored 'startup-metrics.jsonl'
Assert-Ignored 'mcp-health.json'
Assert-Ignored 'permissions-config.json'
Assert-PathPatternNotIgnored 'profiles.json'
Assert-ExistingPathNotIgnored 'docs/superpowers/specs/2026-04-29-copilot-cli-stabilization-design.md'

# Regression checks: ensure .gitignore doesn't mistakenly ignore similarly named files under docs/
Assert-PathPatternNotIgnored 'docs/mcp-health.json'
Assert-PathPatternNotIgnored 'docs/permissions-config.json'

Write-Host 'check-stable-boundary smoke PASS'
