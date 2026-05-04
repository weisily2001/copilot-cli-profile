$ErrorActionPreference = 'Stop'

function Get-DefaultCopilotHome {
  if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    return Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
  }

  return Join-Path $HOME '.copilot'
}

function Get-DistillationPaths {
  param([string]$CopilotHome = $(Get-DefaultCopilotHome))

  return [pscustomobject]@{
    CopilotHome       = $CopilotHome
    MemoryIndexPath   = Join-Path $CopilotHome 'memory\global\memory-index.md'
    GlobalFactsPath   = Join-Path $CopilotHome 'memory\global\global-facts.md'
    ProfilePath       = Join-Path $CopilotHome 'memory\global\profile.md'
    PreferencesPath   = Join-Path $CopilotHome 'memory\global\preferences.json'
    CorrectionsPath   = Join-Path $CopilotHome 'memory\global\corrections.md'
    RulesPath         = Join-Path $CopilotHome 'memory\global\distillation-rules.json'
    SkillRegistryPath = Join-Path $CopilotHome 'skills\skill-registry.json'
  }
}

function Ensure-ParentDirectory {
  param([string]$Path)

  $parent = Split-Path -Path $Path -Parent
  if (-not [string]::IsNullOrWhiteSpace($parent)) {
    [System.IO.Directory]::CreateDirectory($parent) | Out-Null
  }
}

function Read-JsonFile {
  param([string]$Path)

  if (-not (Test-Path $Path)) {
    throw "Missing JSON file: $Path"
  }

  return Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Write-JsonFile {
  param(
    [string]$Path,
    [object]$Value
  )

  Ensure-ParentDirectory -Path $Path
  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  $json = ($Value | ConvertTo-Json -Depth 8) + [Environment]::NewLine
  [System.IO.File]::WriteAllText($Path, $json, $utf8NoBom)
}

function Read-TextFile {
  param([string]$Path)

  if (-not (Test-Path $Path)) {
    return ''
  }

  return Get-Content -Path $Path -Raw -Encoding UTF8
}

function Write-TextFile {
  param(
    [string]$Path,
    [string]$Content
  )

  Ensure-ParentDirectory -Path $Path
  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Add-UniqueLine {
  param(
    [string]$Path,
    [string]$Line
  )

  $content = Read-TextFile -Path $Path
  $lines = if ([string]::IsNullOrWhiteSpace($content)) { @() } else { @($content -split '\r?\n') }
  if ($Line -in $lines) {
    return $false
  }

  $updated = if ([string]::IsNullOrWhiteSpace($content)) {
    $Line + [Environment]::NewLine
  }
  elseif ($content.EndsWith("`r`n") -or $content.EndsWith("`n")) {
    $content + $Line + [Environment]::NewLine
  }
  else {
    $content + [Environment]::NewLine + $Line + [Environment]::NewLine
  }

  Write-TextFile -Path $Path -Content $updated
  return $true
}

function Add-UniqueBlock {
  param(
    [string]$Path,
    [string]$Marker,
    [string]$Block
  )

  $content = Read-TextFile -Path $Path
  if ($content -match [regex]::Escape($Marker)) {
    return $false
  }

  $separator = if ([string]::IsNullOrWhiteSpace($content)) { '' } elseif ($content.EndsWith("`r`n`r`n") -or $content.EndsWith("`n`n")) { '' } else { [Environment]::NewLine }
  $updated = $content + $separator + $Block + [Environment]::NewLine
  Write-TextFile -Path $Path -Content $updated
  return $true
}

function Test-CandidateAllowed {
  param(
    [object]$Candidate,
    [object]$Rules
  )

  $textParts = New-Object System.Collections.Generic.List[string]
  foreach ($property in $Candidate.PSObject.Properties) {
    $value = $property.Value
    if ($null -eq $value) {
      continue
    }

    if ($value -is [string]) {
      if (-not [string]::IsNullOrWhiteSpace($value)) {
        $textParts.Add($value)
      }
      continue
    }

    if ($value -is [System.Collections.IEnumerable]) {
      foreach ($item in $value) {
        if ($item -is [string] -and -not [string]::IsNullOrWhiteSpace($item)) {
          $textParts.Add($item)
        }
      }
    }
  }

  $candidateText = $textParts -join ' '
  foreach ($signal in @($Rules.forbiddenSignals)) {
    if (-not [string]::IsNullOrWhiteSpace([string]$signal) -and $candidateText.Contains([string]$signal)) {
      return $false
    }
  }

  return $true
}

function Get-RouteSpec {
  param(
    [object]$Rules,
    [string]$Kind
  )

  if ($null -eq $Rules -or [string]::IsNullOrWhiteSpace($Kind)) {
    return $null
  }

  if ($Rules.routes.PSObject.Properties.Name -contains $Kind) {
    return $Rules.routes.$Kind
  }

  return $null
}

function Test-RouteTarget {
  param(
    [object]$Route,
    [string]$Target
  )

  if ($null -eq $Route -or [string]::IsNullOrWhiteSpace($Target)) {
    return $false
  }

  return $Target -in @($Route.targets)
}

function Get-CandidateRouteValue {
  param(
    [object]$Candidate,
    [string]$PropertyName
  )

  if ($null -eq $Candidate -or [string]::IsNullOrWhiteSpace($PropertyName)) {
    return $null
  }

  $value = $Candidate.$PropertyName
  if ([string]::IsNullOrWhiteSpace([string]$value)) {
    return $null
  }

  return [string]$value
}

function Test-StablePreferenceDuplicate {
  param(
    [pscustomobject]$Paths,
    [object]$Candidate,
    [object]$Route
  )

  $dedupeField = [string]$Route.dedupeBy
  switch ($dedupeField) {
    'key' {
      if (-not (Test-RouteTarget -Route $Route -Target 'memory\global\preferences.json')) {
        return $false
      }

      $preferences = Read-JsonFile -Path $Paths.PreferencesPath
      if ($preferences.PSObject.Properties.Name -contains $Candidate.key) {
        return ([string]$preferences.($Candidate.key) -eq [string]$Candidate.value)
      }

      return $false
    }
    'summary' {
      if (-not (Test-RouteTarget -Route $Route -Target 'memory\global\profile.md')) {
        return $false
      }

      $summary = if (-not [string]::IsNullOrWhiteSpace([string]$Candidate.summary)) { [string]$Candidate.summary } else { "偏好项：$($Candidate.key) = $($Candidate.value)" }
      $profile = Read-TextFile -Path $Paths.ProfilePath
      return $profile -match [regex]::Escape("- $summary")
    }
    default {
      throw "Unsupported stablePreference dedupeBy '$dedupeField'"
    }
  }
}

function Update-StablePreferenceProfile {
  param(
    [pscustomobject]$Paths,
    [object]$Candidate
  )

  $summary = if (-not [string]::IsNullOrWhiteSpace([string]$Candidate.summary)) {
    [string]$Candidate.summary
  }
  else {
    "偏好项：$($Candidate.key) = $($Candidate.value)"
  }
  $managedLine = "- [$($Candidate.key)] $summary"

  $content = Read-TextFile -Path $Paths.ProfilePath
  $lines = if ([string]::IsNullOrWhiteSpace($content)) { @() } else { @($content -split '\r?\n') }
  $filtered = New-Object System.Collections.Generic.List[string]

  foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line)) {
      continue
    }

    if ($line -match [regex]::Escape("- [$($Candidate.key)] ")) {
      continue
    }

    $filtered.Add($line)
  }

  $filtered.Add($managedLine)
  Write-TextFile -Path $Paths.ProfilePath -Content (($filtered -join [Environment]::NewLine) + [Environment]::NewLine)
}

function Update-StablePreference {
  param(
    [pscustomobject]$Paths,
    [object]$Candidate,
    [object]$Route
  )

  $dedupeValue = Get-CandidateRouteValue -Candidate $Candidate -PropertyName ([string]$Route.dedupeBy)
  if ([string]::IsNullOrWhiteSpace($dedupeValue)) {
    throw "stablePreference candidate missing dedupe field '$($Route.dedupeBy)'"
  }

  if (Test-StablePreferenceDuplicate -Paths $Paths -Candidate $Candidate -Route $Route) {
    return [pscustomobject]@{
      syncIndex     = $false
      registryDirty = $false
      applied       = $false
    }
  }

  $previousValue = $null
  if (Test-RouteTarget -Route $Route -Target 'memory\global\preferences.json') {
    $preferences = Read-JsonFile -Path $Paths.PreferencesPath
    if ($preferences.PSObject.Properties.Name -contains $Candidate.key) {
      $previousValue = [string]$preferences.($Candidate.key)
    }
    if ($preferences.PSObject.Properties.Name -contains $Candidate.key) {
      $preferences.($Candidate.key) = $Candidate.value
    }
    else {
      $preferences | Add-Member -NotePropertyName $Candidate.key -NotePropertyValue $Candidate.value
    }
    Write-JsonFile -Path $Paths.PreferencesPath -Value $preferences
  }

  if (Test-RouteTarget -Route $Route -Target 'memory\global\profile.md') {
    Update-StablePreferenceProfile -Paths $Paths -Candidate $Candidate
  }

  return [pscustomobject]@{
    syncIndex     = Test-RouteTarget -Route $Route -Target 'memory\global\memory-index.md'
    registryDirty = $false
    applied       = $true
  }
}

function Update-Correction {
  param(
    [pscustomobject]$Paths,
    [object]$Candidate,
    [object]$Route
  )

  $dedupeValue = Get-CandidateRouteValue -Candidate $Candidate -PropertyName ([string]$Route.dedupeBy)
  if ([string]::IsNullOrWhiteSpace($dedupeValue)) {
    throw "correction candidate missing dedupe field '$($Route.dedupeBy)'"
  }

  $correctApproach = if (-not [string]::IsNullOrWhiteSpace([string]$Candidate.correctApproach)) {
    [string]$Candidate.correctApproach
  }
  else {
    [string]$Candidate.correct
  }
  $avoidance = if (-not [string]::IsNullOrWhiteSpace([string]$Candidate.avoidance)) {
    [string]$Candidate.avoidance
  }
  else {
    [string]$Candidate.avoid
  }

  if ([string]::IsNullOrWhiteSpace($correctApproach) -or [string]::IsNullOrWhiteSpace($avoidance)) {
    throw "correction candidate '$($Candidate.scenario)' missing correctApproach or avoidance"
  }

  $marker = "触发场景：$($Candidate.scenario)"
  $existingCorrections = if (Test-RouteTarget -Route $Route -Target 'memory\global\corrections.md') { Read-TextFile -Path $Paths.CorrectionsPath } else { '' }
  if ($existingCorrections -match [regex]::Escape($marker)) {
    return [pscustomobject]@{
      syncIndex     = $false
      registryDirty = $false
      applied       = $false
    }
  }

  if (Test-RouteTarget -Route $Route -Target 'memory\global\corrections.md') {
    $block = @(
      "- $marker"
      "  - 正确做法：$correctApproach"
      "  - 避免事项：$avoidance"
    ) -join [Environment]::NewLine
    Add-UniqueBlock -Path $Paths.CorrectionsPath -Marker $marker -Block $block | Out-Null
  }

  return [pscustomobject]@{
    syncIndex     = Test-RouteTarget -Route $Route -Target 'memory\global\memory-index.md'
    registryDirty = $false
    applied       = $true
  }
}

function Update-GlobalFact {
  param(
    [pscustomobject]$Paths,
    [object]$Candidate,
    [object]$Route
  )

  $dedupeValue = Get-CandidateRouteValue -Candidate $Candidate -PropertyName ([string]$Route.dedupeBy)
  if ([string]::IsNullOrWhiteSpace($dedupeValue)) {
    throw "globalFact candidate missing dedupe field '$($Route.dedupeBy)'"
  }

  $factLine = "- $($Candidate.summary)"
  if (Test-RouteTarget -Route $Route -Target 'memory\global\global-facts.md') {
    $existingFacts = Read-TextFile -Path $Paths.GlobalFactsPath
    if ($existingFacts -match [regex]::Escape($factLine)) {
      return [pscustomobject]@{
        syncIndex     = $false
        registryDirty = $false
        applied       = $false
      }
    }
  }

  if (Test-RouteTarget -Route $Route -Target 'memory\global\global-facts.md') {
    Add-UniqueLine -Path $Paths.GlobalFactsPath -Line $factLine | Out-Null
  }

  return [pscustomobject]@{
    syncIndex     = Test-RouteTarget -Route $Route -Target 'memory\global\memory-index.md'
    registryDirty = $false
    applied       = $true
  }
}

function Update-SkillRegistry {
  param(
    [pscustomobject]$Paths,
    [ref]$Registry,
    [object]$Candidate,
    [object]$Route
  )

  $dedupeValue = Get-CandidateRouteValue -Candidate $Candidate -PropertyName ([string]$Route.dedupeBy)
  if ([string]::IsNullOrWhiteSpace($dedupeValue)) {
    throw "skillSignal candidate missing dedupe field '$($Route.dedupeBy)'"
  }

  if ([string]::IsNullOrWhiteSpace([string]$Candidate.purpose)) {
    throw 'skillSignal candidate missing purpose'
  }

  if (-not (Test-RouteTarget -Route $Route -Target 'skills\skill-registry.json')) {
    return [pscustomobject]@{
      syncIndex     = Test-RouteTarget -Route $Route -Target 'memory\global\memory-index.md'
      registryDirty = $false
      applied       = $false
    }
  }

  $existing = @($Registry.Value.skills | Where-Object { $_.name -eq $Candidate.name })
  if ($existing.Count -gt 0) {
    return [pscustomobject]@{
      syncIndex     = Test-RouteTarget -Route $Route -Target 'memory\global\memory-index.md'
      registryDirty = $false
      applied       = $false
    }
  }

  $entry = [pscustomobject]@{
    name          = [string]$Candidate.name
    purpose       = [string]$Candidate.purpose
    triggers      = @($Candidate.triggers | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    scope         = if ([string]::IsNullOrWhiteSpace([string]$Candidate.scope)) { 'global' } else { [string]$Candidate.scope }
    stability     = if ([string]::IsNullOrWhiteSpace([string]$Candidate.stability)) { 'stable' } else { [string]$Candidate.stability }
    relatedDocs   = @($Candidate.relatedDocs | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    relatedMemory = @($Candidate.relatedMemory | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
  }

  if ($entry.relatedMemory.Count -eq 0) {
    $entry.relatedMemory = @('memory\global\memory-index.md')
  }

  $Registry.Value.skills = @($Registry.Value.skills) + $entry

  return [pscustomobject]@{
    syncIndex     = Test-RouteTarget -Route $Route -Target 'memory\global\memory-index.md'
    registryDirty = $true
    applied       = $true
  }
}

function Sync-MemoryIndex {
  param(
    [pscustomobject]$Paths,
    [object]$Registry
  )

  $lines = @(
    '# 全局记忆索引',
    '',
    '## 高频入口',
    '',
    '- 稳定偏好 -> `memory\global\profile.md` -> 先看口语化偏好摘要',
    '- 结构化偏好 -> `memory\global\preferences.json` -> 机器可读键值优先',
    '- 稳定纠错 -> `memory\global\corrections.md` -> 先看触发场景与避免事项',
    '- 全局稳定事实 -> `memory\global\global-facts.md` -> 只保留长期有效事实',
    '',
    '## 技能入口',
    ''
  )

  foreach ($skill in @($Registry.skills)) {
    $lines += "- ``$($skill.name)`` -> `skills\$($skill.name)\SKILL.md` -> $($skill.purpose)"
  }

  Write-TextFile -Path $Paths.MemoryIndexPath -Content (($lines -join [Environment]::NewLine) + [Environment]::NewLine)
}

function Invoke-GlobalMemoryDistillation {
  param(
    [string]$CopilotHome = $(Get-DefaultCopilotHome),
    [array]$Candidates = @(),
    [switch]$ForceIndexSync
  )

  $paths = Get-DistillationPaths -CopilotHome $CopilotHome
  $rules = Read-JsonFile -Path $paths.RulesPath
  $registry = Read-JsonFile -Path $paths.SkillRegistryPath
  if (-not ($registry.PSObject.Properties.Name -contains 'skills')) {
    $registry | Add-Member -NotePropertyName skills -NotePropertyValue @()
  }

  $registryDirty = $false
  $shouldSyncIndex = $false
  $appliedKinds = New-Object System.Collections.Generic.List[string]
  $skippedKinds = New-Object System.Collections.Generic.List[string]

  foreach ($candidate in @($Candidates)) {
    if ($null -eq $candidate -or [string]::IsNullOrWhiteSpace([string]$candidate.kind)) {
      continue
    }

    $route = Get-RouteSpec -Rules $rules -Kind ([string]$candidate.kind)
    if ($null -eq $route) {
      $skippedKinds.Add("$($candidate.kind):$($rules.fallbackRoute)")
      continue
    }

    if (-not (Test-CandidateAllowed -Candidate $candidate -Rules $rules)) {
      $skippedKinds.Add("$($candidate.kind):$($rules.fallbackRoute)")
      continue
    }

    $result = $null
    switch ([string]$candidate.kind) {
      'stablePreference' {
        $result = Update-StablePreference -Paths $paths -Candidate $candidate -Route $route
        $appliedKinds.Add('stablePreference')
      }
      'correction' {
        $result = Update-Correction -Paths $paths -Candidate $candidate -Route $route
        $appliedKinds.Add('correction')
      }
      'globalFact' {
        $result = Update-GlobalFact -Paths $paths -Candidate $candidate -Route $route
        $appliedKinds.Add('globalFact')
      }
      'skillSignal' {
        $result = Update-SkillRegistry -Paths $paths -Registry ([ref]$registry) -Candidate $candidate -Route $route
        $appliedKinds.Add('skillSignal')
      }
    }

    if ($null -ne $result) {
      if ($result.registryDirty) {
        $registryDirty = $true
      }
      if ($result.syncIndex) {
        $shouldSyncIndex = $true
      }
      if (-not $result.applied) {
        if ($appliedKinds.Count -gt 0) {
          $appliedKinds.RemoveAt($appliedKinds.Count - 1)
        }
      }
    }
  }

  if ($registryDirty) {
    Write-JsonFile -Path $paths.SkillRegistryPath -Value $registry
  }
  if ($ForceIndexSync -or $shouldSyncIndex) {
    Sync-MemoryIndex -Paths $paths -Registry $registry
  }

  return [pscustomobject]@{
    updatedRegistry = $paths.SkillRegistryPath
    updatedIndex    = $paths.MemoryIndexPath
    updatedFacts    = $paths.GlobalFactsPath
    appliedKinds    = @($appliedKinds)
    skippedKinds    = @($skippedKinds)
  }
}





