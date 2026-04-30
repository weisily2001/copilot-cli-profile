# Documentation Smoke Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 `.copilot` 仓库新增独立的 `diagnostics\check-documentation-smoke.ps1`，稳定检查 README、startup-observability、mcp-observability 三份文档的 6 条关键事实。

**Architecture:** 继续沿用 diagnostics 目录现有的 PowerShell smoke 模式，只新增一个脚本，不引入新框架，也不修改现有文档正文。脚本通过 `Split-Path $PSScriptRoot -Parent` 解析仓库根目录，使用 `Get-Content -Raw -Encoding UTF8` 读取文档，再用字面量断言逐项检查；失败立即 `throw`，成功输出固定 PASS 标记。

**Tech Stack:** PowerShell 5+/7、现有 diagnostics smoke 模式、Git

---

## 文件结构

- **Create:** `C:\Users\HP\.copilot\.worktrees\doc-smoke-v1\diagnostics\check-documentation-smoke.ps1`
- **Reference only:** `C:\Users\HP\.copilot\.worktrees\doc-smoke-v1\README.md`
- **Reference only:** `C:\Users\HP\.copilot\.worktrees\doc-smoke-v1\startup-observability.md`
- **Reference only:** `C:\Users\HP\.copilot\.worktrees\doc-smoke-v1\mcp-observability.md`
- **Regression run:** `C:\Users\HP\.copilot\.worktrees\doc-smoke-v1\diagnostics\inspect-profiles-smoke.ps1`
- **Regression run:** `C:\Users\HP\.copilot\.worktrees\doc-smoke-v1\diagnostics\check-mcp-health-smoke.ps1`

## 断言清单

实现时只检查以下 6 条事实，禁止额外扩大：

1. `README.md` 包含 `profiles.json`
2. `README.md` 包含 `check-mcp-health.ps1`
3. `README.md` 包含 `默认写入当前仓库根目录下的 ` + ``mcp-health.json```
4. `startup-observability.md` 包含 `mcp-observability.md`
5. `mcp-observability.md` 文件存在
6. `mcp-observability.md` 包含 `默认写入当前仓库根目录下的 ` + ``mcp-health.json```

### Task 1: 实现独立文档 smoke

**Files:**
- Create: `C:\Users\HP\.copilot\.worktrees\doc-smoke-v1\diagnostics\check-documentation-smoke.ps1`
- Reference: `C:\Users\HP\.copilot\.worktrees\doc-smoke-v1\README.md`
- Reference: `C:\Users\HP\.copilot\.worktrees\doc-smoke-v1\startup-observability.md`
- Reference: `C:\Users\HP\.copilot\.worktrees\doc-smoke-v1\mcp-observability.md`

- [ ] **Step 1: 写出会失败的 smoke 骨架**

```powershell
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
$readmePath = Join-Path $repoRoot 'README.md'
$startupPath = Join-Path $repoRoot 'startup-observability.md'
$mcpObservabilityPath = Join-Path $repoRoot 'mcp-observability.md'

$readme = Get-Content -Path $readmePath -Raw -Encoding UTF8
$startup = Get-Content -Path $startupPath -Raw -Encoding UTF8
$mcpObservability = Get-Content -Path $mcpObservabilityPath -Raw -Encoding UTF8

Assert-ContainsLiteral -Content $readme -Literal 'profiles.json' -Context 'README.md'
Assert-ContainsLiteral -Content $readme -Literal 'check-mcp-health.ps1' -Context 'README.md'
Assert-ContainsLiteral -Content $readme -Literal '默认写入当前仓库根目录下的 `mcp-health.json`' -Context 'README.md'
Assert-ContainsLiteral -Content $startup -Literal 'mcp-observability.md' -Context 'startup-observability.md'
Assert-ContainsLiteral -Content $mcpObservability -Literal '默认写入当前仓库根目录下的 `mcp-health.json`' -Context 'mcp-observability.md'

Write-Host 'documentation smoke PASS'
```

- [ ] **Step 2: 运行骨架，确认因实现缺失失败**

Run:

```powershell
Set-Location C:\Users\HP\.copilot\.worktrees\doc-smoke-v1
powershell -ExecutionPolicy Bypass -File .\diagnostics\check-documentation-smoke.ps1
```

Expected: FAIL，错误包含 `Assert-ContainsLiteral` 未定义或未识别，证明当前仍处于红灯阶段。

- [ ] **Step 3: 写最小实现，让断言真正可执行**

```powershell
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

  return Get-Content -Path $Path -Raw -Encoding UTF8
}

function Assert-ContainsLiteral {
  param(
    [string]$Content,
    [string]$Literal,
    [string]$Context
  )

  if ($Content -notmatch [regex]::Escape($Literal)) {
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
```

- [ ] **Step 4: 单独运行新 smoke，确认通过**

Run:

```powershell
Set-Location C:\Users\HP\.copilot\.worktrees\doc-smoke-v1
powershell -ExecutionPolicy Bypass -File .\diagnostics\check-documentation-smoke.ps1
```

Expected:

```text
documentation smoke PASS
```

- [ ] **Step 5: 保持改动未提交，进入联动回归**

Expected: 当前只新增 `diagnostics\check-documentation-smoke.ps1`，还不提交，先用 Task 2 完成三脚本回归，避免提交后再返工。

### Task 2: 运行回归并完成收口

**Files:**
- Verify: `C:\Users\HP\.copilot\.worktrees\doc-smoke-v1\diagnostics\inspect-profiles-smoke.ps1`
- Verify: `C:\Users\HP\.copilot\.worktrees\doc-smoke-v1\diagnostics\check-mcp-health-smoke.ps1`
- Verify: `C:\Users\HP\.copilot\.worktrees\doc-smoke-v1\diagnostics\check-documentation-smoke.ps1`

- [ ] **Step 1: 运行现有 profile smoke**

Run:

```powershell
Set-Location C:\Users\HP\.copilot\.worktrees\doc-smoke-v1
powershell -ExecutionPolicy Bypass -File .\diagnostics\inspect-profiles-smoke.ps1
```

Expected:

```text
inspect-profiles smoke PASS
```

- [ ] **Step 2: 运行现有 MCP health smoke**

Run:

```powershell
Set-Location C:\Users\HP\.copilot\.worktrees\doc-smoke-v1
powershell -ExecutionPolicy Bypass -File .\diagnostics\check-mcp-health-smoke.ps1
```

Expected:

```text
check-mcp-health smoke PASS
```

- [ ] **Step 3: 再次运行新的 documentation smoke**

Run:

```powershell
Set-Location C:\Users\HP\.copilot\.worktrees\doc-smoke-v1
powershell -ExecutionPolicy Bypass -File .\diagnostics\check-documentation-smoke.ps1
```

Expected:

```text
documentation smoke PASS
```

- [ ] **Step 4: 检查没有额外运行产物或文档改动**

Run:

```powershell
Set-Location C:\Users\HP\.copilot\.worktrees\doc-smoke-v1
git --no-pager status --short
```

Expected: 只出现本轮计划内的新增脚本变更；不能出现新的 `mcp-health.json`、临时 fixture 目录或 README / `startup-observability.md` / `mcp-observability.md` 正文改动。

- [ ] **Step 5: 提交回归验证收口**

```powershell
Set-Location C:\Users\HP\.copilot\.worktrees\doc-smoke-v1
git --no-pager add -- diagnostics\check-documentation-smoke.ps1
git --no-pager commit -m "新增文档检查 smoke 脚本" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

## 自检结果

### Spec coverage

- 独立 `diagnostics\check-documentation-smoke.ps1`：Task 1
- 6 条最小关键断言：Task 1 Step 1 / Step 3
- 只用 PowerShell 原生能力：Task 1 Step 3
- 单脚本运行通过：Task 1 Step 4
- 联动三条 smoke 回归：Task 2 Step 1-3
- 不修改现有文档正文、不产生新产物：Task 2 Step 4

### Placeholder scan

- 已检查，无 `TODO`、`TBD`、`implement later`、`add tests for above` 之类占位表述。

### Type consistency

- 统一使用 `Read-Utf8File` / `Assert-ContainsLiteral`。
- 统一使用 `$repoRoot = Split-Path $PSScriptRoot -Parent`。
- PASS 标记统一为 `documentation smoke PASS`。
