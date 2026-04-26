param()

$ErrorActionPreference = 'Stop'
$shared = 'C:\Users\HP\.copilot\hooks\ecc-memory\shared.ps1'

if (-not (Test-Path $shared)) {
  throw "Missing shared helper: $shared"
}

. $shared

$tempRoot = Join-Path $env:TEMP 'hook-resolution-smoke'
$projectsRoot = Join-Path $tempRoot 'projects'
$fixturesRoot = Join-Path $tempRoot 'fixtures'
$cachePath = Join-Path $tempRoot 'project-context-cache.json'
$cacheProjectDir = Join-Path $projectsRoot 'hook-resolution-smoke-cache'
$scanProjectDir = Join-Path $projectsRoot 'hook-resolution-smoke-scan'
$parentProjectDir = Join-Path $projectsRoot 'hook-resolution-smoke-parent'
$childProjectDir = Join-Path $projectsRoot 'hook-resolution-smoke-child'
$mismatchProjectDir = Join-Path $projectsRoot 'hook-resolution-smoke-dir-name'
$duplicateOneProjectDir = Join-Path $projectsRoot 'hook-resolution-smoke-duplicate-one'
$duplicateTwoProjectDir = Join-Path $projectsRoot 'hook-resolution-smoke-duplicate-two'
$cacheFixtureRoot = Join-Path $fixturesRoot 'cache-match'
$scanFixtureRoot = Join-Path $fixturesRoot 'scan-match'
$overlapParentRoot = Join-Path $fixturesRoot 'overlap-parent'
$overlapChildRoot = Join-Path $overlapParentRoot 'overlap-child'
$mismatchFixtureRoot = Join-Path $fixturesRoot 'mismatch-root'
$mismatchProjectKey = 'hook-resolution-smoke-custom-key'
$duplicateFixtureRoot = Join-Path $fixturesRoot 'duplicate-root'

try {
  $script:ProjectContextCachePath = $cachePath
  New-Item -ItemType Directory -Force -Path $projectsRoot, $fixturesRoot, $cacheProjectDir, $scanProjectDir, $parentProjectDir, $childProjectDir, $mismatchProjectDir, $duplicateOneProjectDir, $duplicateTwoProjectDir, $cacheFixtureRoot, $scanFixtureRoot, $overlapParentRoot, $overlapChildRoot, $mismatchFixtureRoot, $duplicateFixtureRoot | Out-Null

  @'
{
  "projectKey": "hook-resolution-smoke-cache",
  "projectRoot": "__CACHE_ROOT__"
}
'@.Replace('__CACHE_ROOT__', $cacheFixtureRoot.Replace('\', '\\')) | Set-Content -Path (Join-Path $cacheProjectDir 'project.json') -Encoding UTF8

  @'
{
  "projectKey": "hook-resolution-smoke-scan",
  "projectRoot": "__SCAN_ROOT__"
}
'@.Replace('__SCAN_ROOT__', $scanFixtureRoot.Replace('\', '\\')) | Set-Content -Path (Join-Path $scanProjectDir 'project.json') -Encoding UTF8

  @'
{
  "projectKey": "hook-resolution-smoke-parent",
  "projectRoot": "__PARENT_ROOT__"
}
'@.Replace('__PARENT_ROOT__', $overlapParentRoot.Replace('\', '\\')) | Set-Content -Path (Join-Path $parentProjectDir 'project.json') -Encoding UTF8

  @'
{
  "projectKey": "hook-resolution-smoke-child",
  "projectRoot": "__CHILD_ROOT__"
}
'@.Replace('__CHILD_ROOT__', $overlapChildRoot.Replace('\', '\\')) | Set-Content -Path (Join-Path $childProjectDir 'project.json') -Encoding UTF8

  @'
{
  "projectKey": "__MISMATCH_KEY__",
  "projectRoot": "__MISMATCH_ROOT__"
}
'@.Replace('__MISMATCH_KEY__', $mismatchProjectKey).Replace('__MISMATCH_ROOT__', $mismatchFixtureRoot.Replace('\', '\\')) | Set-Content -Path (Join-Path $mismatchProjectDir 'project.json') -Encoding UTF8

  @'
{
  "projectKey": "hook-resolution-smoke-duplicate",
  "projectRoot": "__DUPLICATE_ROOT__"
}
'@.Replace('__DUPLICATE_ROOT__', $duplicateFixtureRoot.Replace('\', '\\')) | Set-Content -Path (Join-Path $duplicateOneProjectDir 'project.json') -Encoding UTF8

  @'
{
  "projectKey": "hook-resolution-smoke-duplicate",
  "projectRoot": "__DUPLICATE_ROOT__"
}
'@.Replace('__DUPLICATE_ROOT__', $duplicateFixtureRoot.Replace('\', '\\')) | Set-Content -Path (Join-Path $duplicateTwoProjectDir 'project.json') -Encoding UTF8

  @'
{
  "projectKey": "hook-resolution-smoke-cache",
  "projectRoot": "__CACHE_ROOT__"
}
'@.Replace('__CACHE_ROOT__', $cacheFixtureRoot.Replace('\', '\\')) | Set-Content -Path $cachePath -Encoding UTF8

  $cached = Resolve-ProjectContextFast -Path (Join-Path $cacheFixtureRoot 'child') -ProjectsRoot $projectsRoot
  if ($null -eq $cached) {
    throw 'Resolve-ProjectContextFast returned null for recent-project hit'
  }

  if ($cached.ProjectKey -ne 'hook-resolution-smoke-cache') {
    throw "Expected recent-project hit, got '$($cached.ProjectKey)'"
  }

  if ($cached.ProjectRoot -ne $cacheFixtureRoot) {
    throw "Unexpected cached ProjectRoot '$($cached.ProjectRoot)'"
  }

  @'
{
  "projectKey": "hook-resolution-smoke-parent",
  "projectRoot": "__PARENT_ROOT__"
}
'@.Replace('__PARENT_ROOT__', $overlapParentRoot.Replace('\', '\\')) | Set-Content -Path $cachePath -Encoding UTF8

  $overlap = Resolve-ProjectContextFast -Path (Join-Path $overlapChildRoot 'child') -ProjectsRoot $projectsRoot
  if ($null -eq $overlap) {
    throw 'Resolve-ProjectContextFast returned null for overlap match'
  }

  if ($overlap.ProjectKey -ne 'hook-resolution-smoke-child') {
    throw "Expected overlap child hit, got '$($overlap.ProjectKey)'"
  }

  if ($overlap.ProjectRoot -ne $overlapChildRoot) {
    throw "Unexpected overlap ProjectRoot '$($overlap.ProjectRoot)'"
  }

  @'
{
  "projectKey": "hook-resolution-smoke-cache",
  "projectRoot": "__CACHE_ROOT__"
}
'@.Replace('__CACHE_ROOT__', $cacheFixtureRoot.Replace('\', '\\')) | Set-Content -Path $cachePath -Encoding UTF8

  $scanned = Resolve-ProjectContextFast -Path (Join-Path $scanFixtureRoot 'child') -ProjectsRoot $projectsRoot
  if ($null -eq $scanned) {
    throw 'Resolve-ProjectContextFast returned null for fallback scan'
  }

  if ($scanned.ProjectKey -ne 'hook-resolution-smoke-scan') {
    throw "Expected fallback scan hit, got '$($scanned.ProjectKey)'"
  }

  if ($scanned.ProjectRoot -ne $scanFixtureRoot) {
    throw "Unexpected scanned ProjectRoot '$($scanned.ProjectRoot)'"
  }

  $mismatch = Resolve-ProjectContextFast -Path (Join-Path $mismatchFixtureRoot 'child') -ProjectsRoot $projectsRoot
  if ($null -eq $mismatch) {
    throw 'Resolve-ProjectContextFast returned null for mismatch project'
  }

  if ($mismatch.ProjectKey -ne $mismatchProjectKey) {
    throw "Expected mismatch project key '$mismatchProjectKey', got '$($mismatch.ProjectKey)'"
  }

  if ($mismatch.ProjectDir -ne $mismatchProjectDir) {
    throw "Expected mismatch ProjectDir '$mismatchProjectDir', got '$($mismatch.ProjectDir)'"
  }

  Write-LastSessionMetadata -ProjectKey $mismatch.ProjectKey -ProjectRoot $mismatch.ProjectRoot -ProjectDir $mismatch.ProjectDir -EventName 'sessionStart' -ProjectsRoot $projectsRoot
  $mismatchLastSessionPath = Join-Path $mismatchProjectDir 'last-session.json'
  if (-not (Test-Path $mismatchLastSessionPath)) {
    throw "Expected mismatch last-session metadata at '$mismatchLastSessionPath'"
  }

  $writtenCache = Get-Content -Path $cachePath -Raw | ConvertFrom-Json
  if ($writtenCache.projectKey -ne $mismatchProjectKey) {
    throw "Expected cache projectKey '$mismatchProjectKey', got '$($writtenCache.projectKey)'"
  }

  if ($writtenCache.projectRoot -ne $mismatchFixtureRoot) {
    throw "Expected cache projectRoot '$mismatchFixtureRoot', got '$($writtenCache.projectRoot)'"
  }

  if ($writtenCache.projectDir -ne $mismatchProjectDir) {
    throw "Expected cache projectDir '$mismatchProjectDir', got '$($writtenCache.projectDir)'"
  }

  $mismatchFromWrittenCache = Resolve-ProjectContextFast -Path (Join-Path $mismatchFixtureRoot 'child') -ProjectsRoot $projectsRoot
  if ($null -eq $mismatchFromWrittenCache) {
    throw 'Resolve-ProjectContextFast returned null for written cache replay'
  }

  if ($mismatchFromWrittenCache.ProjectDir -ne $mismatchProjectDir) {
    throw "Expected written cache replay to return '$mismatchProjectDir', got '$($mismatchFromWrittenCache.ProjectDir)'"
  }

  @'
{
  "projectKey": "__MISMATCH_KEY__",
  "projectRoot": "__MISMATCH_ROOT__"
}
'@.Replace('__MISMATCH_KEY__', $mismatchProjectKey).Replace('__MISMATCH_ROOT__', $mismatchFixtureRoot.Replace('\', '\\')) | Set-Content -Path $cachePath -Encoding UTF8

  $mismatchFromCache = Resolve-ProjectContextFast -Path (Join-Path $mismatchFixtureRoot 'child') -ProjectsRoot $projectsRoot
  if ($null -eq $mismatchFromCache) {
    throw 'Resolve-ProjectContextFast returned null for mismatch cache hydration'
  }

  if ($mismatchFromCache.ProjectDir -ne $mismatchProjectDir) {
    throw "Expected mismatch ProjectDir to be hydrated from scan, got '$($mismatchFromCache.ProjectDir)'"
  }

  $staleProjectDir = Join-Path $projectsRoot 'hook-resolution-smoke-stale-dir'
  New-Item -ItemType Directory -Force -Path $staleProjectDir | Out-Null
  @'
{
  "projectKey": "__MISMATCH_KEY__",
  "projectRoot": "__MISMATCH_ROOT__",
  "projectDir": "__STALE_DIR__"
}
'@.Replace('__MISMATCH_KEY__', $mismatchProjectKey).Replace('__MISMATCH_ROOT__', $mismatchFixtureRoot.Replace('\', '\\')).Replace('__STALE_DIR__', $staleProjectDir.Replace('\', '\\')) | Set-Content -Path $cachePath -Encoding UTF8

  $mismatchFromStaleCache = Resolve-ProjectContextFast -Path (Join-Path $mismatchFixtureRoot 'child') -ProjectsRoot $projectsRoot
  if ($null -eq $mismatchFromStaleCache) {
    throw 'Resolve-ProjectContextFast returned null for stale cache repair'
  }

  if ($mismatchFromStaleCache.ProjectDir -ne $mismatchProjectDir) {
    throw "Expected stale cache ProjectDir to be repaired to '$mismatchProjectDir', got '$($mismatchFromStaleCache.ProjectDir)'"
  }

  @'
{
  "projectKey": "hook-resolution-smoke-duplicate",
  "projectRoot": "__DUPLICATE_ROOT__",
  "projectDir": "__DUPLICATE_DIR__"
}
'@.Replace('__DUPLICATE_ROOT__', $duplicateFixtureRoot.Replace('\', '\\')).Replace('__DUPLICATE_DIR__', $duplicateOneProjectDir.Replace('\', '\\')) | Set-Content -Path $cachePath -Encoding UTF8

  $duplicate = Resolve-ProjectContextFast -Path (Join-Path $duplicateFixtureRoot 'child') -ProjectsRoot $projectsRoot
  if ($null -ne $duplicate) {
    throw 'Expected duplicate same-root project directories to be treated as ambiguous'
  }
}
finally {
  if (Test-Path $tempRoot) {
    Remove-Item $tempRoot -Recurse -Force
  }
}

Write-Host 'hook-resolution smoke PASS'
