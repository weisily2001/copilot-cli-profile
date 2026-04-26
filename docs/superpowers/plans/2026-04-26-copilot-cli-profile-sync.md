# Copilot CLI Profile Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `C:\Users\HP\.copilot` 整理成可公开推送到 GitHub 的稳定配置仓库 `copilot-cli-profile`，支持跨主机同步、后续 PR 和稳定回滚。

**Architecture:** 继续以当前 `.copilot` 目录作为仓库根目录，先收紧版本边界，再补充跨主机使用说明，随后把稳定配置分批纳入 Git 并通过 GitHub API 创建远端仓库。最终以 `main` 作为稳定入口，并打出首个回滚标签。

**Tech Stack:** Git, GitHub REST API, PowerShell 5.1/7, 现有 `.ps1` 诊断脚本, Markdown 文档

---

### Task 1: 收紧公开仓库的版本边界

**Files:**
- Modify: `.gitignore`
- Verify: `config.json`
- Verify: `memory\projects\desktop\project.json`
- Verify: `memory\projects\desktop\last-session.json`

- [ ] **Step 1: 记录当前会泄漏进 Git 的运行态文件**

Run:

```powershell
Set-Location 'C:\Users\HP\.copilot'
git --no-pager status --short
```

Expected: 输出里能看到 `logs\`、`session-state\`、`hook-metrics.jsonl`、`startup-metrics.jsonl`、`command-history-state.json`、`config.json` 等运行态或主机态内容。

- [ ] **Step 2: 把 `.gitignore` 扩展成公开仓库边界**

Replace `.gitignore` with:

```gitignore
.worktrees/
logs/
session-state/
hook-metrics.jsonl
startup-metrics.jsonl
command-history-state.json
config.json
memory/project-context-cache.json
memory/projects/*/last-session.json
memory/projects/*/project.json
ide/
jb/
```

- [ ] **Step 3: 重新检查忽略规则是否生效**

Run:

```powershell
Set-Location 'C:\Users\HP\.copilot'
git --no-pager status --short
git add -n .
```

Expected: `git status --short` 不再把已忽略的运行态目录和文件当成待纳入版本库的目标；`git add -n .` 的预演结果只剩稳定配置、脚本、模板、技能和文档。

- [ ] **Step 4: 提交版本边界调整**

Run:

```powershell
Set-Location 'C:\Users\HP\.copilot'
git add .gitignore
git commit -m "chore: 收紧公开仓库边界" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

Expected: 生成只包含 `.gitignore` 的独立提交，便于后续回看版本边界。

### Task 2: 补齐跨主机使用和回滚说明

**Files:**
- Create: `README.md`

- [ ] **Step 1: 写入公开仓库说明文档**

Create `README.md` with:

```markdown
# Copilot CLI Profile

这是一套可跨主机复用的 Copilot CLI 配置仓库。

仓库包含稳定配置、诊断脚本、模板、技能、代理和治理文档。

仓库不包含运行时日志、会话状态、自动生成的本机配置缓存和其他临时产物。

## 使用方式

把仓库克隆到用户目录下的 `.copilot` 位置：

```powershell
git clone https://github.com/weisily2001/copilot-cli-profile.git $HOME\.copilot
```

如果目标主机已经有 `.copilot` 目录，先备份原目录，再执行覆盖式迁移。

首次启动 Copilot CLI 后，程序会自动生成本机自己的 `config.json`。

## 更新方式

拉取稳定更新：

```powershell
Set-Location $HOME\.copilot
git pull origin main
```

试验新改动：

```powershell
Set-Location $HOME\.copilot
git checkout -b feat/update-profile
```

## 回滚方式

查看可回滚标签：

```powershell
Set-Location $HOME\.copilot
git tag
```

回到稳定标签：

```powershell
Set-Location $HOME\.copilot
git checkout baseline-2026-04-26
```

如果要回到稳定分支最新状态：

```powershell
Set-Location $HOME\.copilot
git checkout main
git pull origin main
```
```

- [ ] **Step 2: 检查 README 是否覆盖克隆、更新和回滚路径**

Run:

```powershell
Set-Location 'C:\Users\HP\.copilot'
Get-Content .\README.md
```

Expected: README 明确写出仓库用途、跨主机克隆、更新、分支试验和标签回滚命令。

- [ ] **Step 3: 提交说明文档**

Run:

```powershell
Set-Location 'C:\Users\HP\.copilot'
git add README.md
git commit -m "docs: 添加仓库使用说明" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

Expected: 生成只包含 README 的独立文档提交。

### Task 3: 纳入稳定配置并验证可运行基线

**Files:**
- Add: `agents\`
- Add: `diagnostics\`
- Add: `docs\`
- Add: `hooks\`
- Add: `memory\global\`
- Add: `memory\projects\desktop\decisions.md`
- Add: `memory\projects\desktop\handoff.md`
- Add: `memory\projects\desktop\overview.md`
- Add: `memory\projects\desktop\state.md`
- Add: `mcp-config.json`
- Add: `mcp-config.remote.json`
- Add: `lsp-config.json`
- Add: `settings.json`
- Add: `skills\`
- Add: `templates\`
- Add: `copilot-instructions.md`
- Add: `memory-governance.md`
- Add: `memory-lifecycle.md`
- Add: `startup-observability.md`
- Add: `agent-orchestration-observability.md`

- [ ] **Step 1: 预演稳定内容的纳入范围**

Run:

```powershell
Set-Location 'C:\Users\HP\.copilot'
git add -n agents diagnostics docs hooks memory\global memory\projects\desktop\decisions.md memory\projects\desktop\handoff.md memory\projects\desktop\overview.md memory\projects\desktop\state.md mcp-config.json mcp-config.remote.json lsp-config.json settings.json skills templates copilot-instructions.md memory-governance.md memory-lifecycle.md startup-observability.md agent-orchestration-observability.md
```

Expected: 预演结果只包含稳定配置和文档，不包含 `config.json`、`logs`、`session-state` 或 `memory\projects\desktop\project.json`、`last-session.json`。

- [ ] **Step 2: 运行现有 smoke，确认纳入前基线可用**

Run:

```powershell
Set-Location 'C:\Users\HP\.copilot'
powershell -ExecutionPolicy Bypass -File .\diagnostics\inspect-login-state-smoke.ps1
powershell -ExecutionPolicy Bypass -File .\diagnostics\hook-resolution-smoke.ps1
powershell -ExecutionPolicy Bypass -File .\diagnostics\hook-metrics-smoke.ps1
powershell -ExecutionPolicy Bypass -File .\diagnostics\measure-startup-smoke.ps1
powershell -ExecutionPolicy Bypass -File .\diagnostics\evaluate-agent-orchestration-smoke.ps1
```

Expected: 五个 smoke 都通过，没有新增解析错误或路径错误。

- [ ] **Step 3: 实际纳入稳定内容**

Run:

```powershell
Set-Location 'C:\Users\HP\.copilot'
git add agents diagnostics docs hooks memory\global memory\projects\desktop\decisions.md memory\projects\desktop\handoff.md memory\projects\desktop\overview.md memory\projects\desktop\state.md mcp-config.json mcp-config.remote.json lsp-config.json settings.json skills templates copilot-instructions.md memory-governance.md memory-lifecycle.md startup-observability.md agent-orchestration-observability.md
git --no-pager status --short
```

Expected: 暂存区只出现稳定内容，`git status --short` 可清楚显示当前准备提交的基线集合。

- [ ] **Step 4: 提交当前稳定配置基线**

Run:

```powershell
Set-Location 'C:\Users\HP\.copilot'
git commit -m "feat: 发布 copilot cli 配置基线" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

Expected: 生成承载当前稳定配置和文档的主提交，作为远端同步的首个完整基线。

### Task 4: 创建 GitHub 公开仓库并推送 `main`

**Files:**
- Remote state only

- [ ] **Step 1: 用 GitHub API 创建公开仓库 `copilot-cli-profile`**

Run:

```powershell
Set-Location 'C:\Users\HP\.copilot'
$token = if ($env:GITHUB_TOKEN) { $env:GITHUB_TOKEN } elseif ($env:GH_TOKEN) { $env:GH_TOKEN } else { throw 'Missing GITHUB_TOKEN or GH_TOKEN' }
$repo = curl.exe -s https://api.github.com/repos/weisily2001/copilot-cli-profile `
  -H "Accept: application/vnd.github+json" `
  -H "Authorization: Bearer $token" `
  -H "X-GitHub-Api-Version: 2022-11-28" | ConvertFrom-Json
if (-not $repo.clone_url) {
  $body = @{ name = 'copilot-cli-profile'; private = $false; auto_init = $false; description = 'Portable Copilot CLI configuration, scripts, templates, and docs.' } | ConvertTo-Json -Compress
  $repo = curl.exe -s -X POST https://api.github.com/user/repos `
    -H "Accept: application/vnd.github+json" `
    -H "Authorization: Bearer $token" `
    -H "X-GitHub-Api-Version: 2022-11-28" `
    -d $body | ConvertFrom-Json
}
if (-not $repo.clone_url) { throw 'GitHub repository creation failed' }
$repo.clone_url
```

Expected: 输出 `https://github.com/weisily2001/copilot-cli-profile.git`。

- [ ] **Step 2: 绑定远端并推送 `main`**

Run:

```powershell
Set-Location 'C:\Users\HP\.copilot'
git remote remove origin 2>$null
git remote add origin https://github.com/weisily2001/copilot-cli-profile.git
git push -u origin main
```

Expected: 输出里出现 `branch 'main' set up to track 'origin/main'`。

- [ ] **Step 3: 检查远端状态**

Run:

```powershell
Set-Location 'C:\Users\HP\.copilot'
git remote -v
git ls-remote --heads origin main
```

Expected: `origin` 指向 `copilot-cli-profile`，且远端存在 `main`。

### Task 5: 固化首个稳定回滚点

**Files:**
- Git tag only

- [ ] **Step 1: 为首个稳定基线打标签**

Run:

```powershell
Set-Location 'C:\Users\HP\.copilot'
git tag -a baseline-2026-04-26 -m "公开同步前的首个稳定配置基线"
```

Expected: 本地出现 `baseline-2026-04-26` 标签。

- [ ] **Step 2: 推送标签并验证回滚入口**

Run:

```powershell
Set-Location 'C:\Users\HP\.copilot'
git push origin baseline-2026-04-26
git tag --list
git ls-remote --tags origin baseline-2026-04-26
```

Expected: 本地和远端都能看到 `baseline-2026-04-26` 标签。

- [ ] **Step 3: 记录最终仓库状态**

Run:

```powershell
Set-Location 'C:\Users\HP\.copilot'
git --no-pager log --oneline --decorate -n 5
git --no-pager status --short
```

Expected: 最近历史包含设计文档提交、仓库边界提交、README 提交和配置基线提交；工作区保持干净或只剩用户明确保留的未跟踪内容。
