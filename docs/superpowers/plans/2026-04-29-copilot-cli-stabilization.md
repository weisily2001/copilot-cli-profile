# Copilot CLI 稳定化收口实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 Copilot CLI 当前已验证有效的配置、诊断与记忆治理能力收口为长期可用的稳定主线。

**Architecture:** 先收紧仓库边界，再固化稳定配置与 MCP 健康检查基线，随后压缩记忆与运行态噪音，最后以完整 smoke 套件和工作区复查确认主线可长期使用。计划只保留高价值、已验证能力，不继续引入新的实验性改造。

**Tech Stack:** Git、PowerShell 5.1/7、Copilot CLI 配置文件、现有 diagnostics smoke、Markdown 文档

---

### Task 1: 收紧稳定主线边界

**Files:**
- Modify: `.gitignore`
- Add/Verify: `diagnostics\check-stable-boundary-smoke.ps1`
- Verify: `docs\superpowers\specs\2026-04-29-copilot-cli-stabilization-design.md`

- [ ] **Step 1: 补齐稳定主线的忽略边界**

Run:
```powershell
Set-Location 'C:\Users\HP\.copilot'
git --no-pager status --short
```

Expected: 能看见运行态产物与稳定文件混杂，需要进一步收紧忽略规则。

- [ ] **Step 2: 固化边界 smoke**

Run:
```powershell
Set-Location 'C:\Users\HP\.copilot'
powershell -ExecutionPolicy Bypass -File .\diagnostics\check-stable-boundary-smoke.ps1
```

Expected: `check-stable-boundary smoke PASS`

### Task 2: 固化稳定配置面

**Files:**
- Modify: `settings.json`
- Add: `profiles.json`
- Verify: `lsp-config.json`
- Add/Verify: `diagnostics\check-stable-config-smoke.ps1`

- [ ] **Step 1: 固化默认 profile 与 hooks 主线**

Run:
```powershell
Set-Location 'C:\Users\HP\.copilot'
Get-Content .\settings.json
Get-Content .\profiles.json
Get-Content .\lsp-config.json
```

Expected: `settings.json` 只保留稳定 hooks；`profiles.json` 仅保留 `default`、`research`、`heavy`；`lsp-config.json` 维持 `typescript` 与 `python`。

- [ ] **Step 2: 运行稳定配置 smoke**

Run:
```powershell
Set-Location 'C:\Users\HP\.copilot'
powershell -ExecutionPolicy Bypass -File .\diagnostics\check-stable-config-smoke.ps1
```

Expected: `check-stable-config smoke PASS`

### Task 3: 固化 MCP 健康检查基线

**Files:**
- Add/Verify: `mcp-health-rules.json`
- Add/Verify: `diagnostics\check-mcp-health.ps1`
- Add/Verify: `diagnostics\check-mcp-health-smoke.ps1`
- Add/Verify: `diagnostics\check-mcp-health-default-paths-smoke.ps1`
- Add/Verify: `diagnostics\check-mcp-health-remote-failure-smoke.ps1`

- [ ] **Step 1: 固化默认、远程失败与 UTF-8 兼容性验证入口**

Run:
```powershell
Set-Location 'C:\Users\HP\.copilot'
powershell -ExecutionPolicy Bypass -File .\diagnostics\check-mcp-health-smoke.ps1
powershell -ExecutionPolicy Bypass -File .\diagnostics\check-mcp-health-default-paths-smoke.ps1
powershell -ExecutionPolicy Bypass -File .\diagnostics\check-mcp-health-remote-failure-smoke.ps1
```

Expected:
- `check-mcp-health smoke PASS`
- `check-mcp-health default paths smoke PASS`
- `check-mcp-health remote failure smoke PASS`

### Task 4: 收口记忆与运行产物

**Files:**
- Modify: `memory\global\preferences.json`
- Modify: `memory\global\profile.md`
- Modify: `memory\projects\desktop\decisions.md`
- Modify: `memory\projects\desktop\handoff.md`
- Modify: `memory\projects\desktop\state.md`
- Verify: `diagnostics\hook-resolution-smoke.ps1`
- Verify: `diagnostics\hook-metrics-smoke.ps1`
- Verify: `diagnostics\measure-startup-smoke.ps1`

- [ ] **Step 1: 压缩项目记忆并校正恢复语义**

Run:
```powershell
Set-Location 'C:\Users\HP\.copilot'
Get-Content .\memory\projects\desktop\handoff.md
Get-Content .\memory\projects\desktop\state.md
```

Expected: `handoff.md` 与 `state.md` 对齐当前 HEAD，不再要求重复执行已完成的清理动作。

- [ ] **Step 2: 运行 hooks 与启动观测 smoke**

Run:
```powershell
Set-Location 'C:\Users\HP\.copilot'
powershell -ExecutionPolicy Bypass -File .\diagnostics\hook-resolution-smoke.ps1
powershell -ExecutionPolicy Bypass -File .\diagnostics\hook-metrics-smoke.ps1
powershell -ExecutionPolicy Bypass -File .\diagnostics\measure-startup-smoke.ps1
```

Expected:
- `hook-resolution smoke PASS`
- `hook-metrics smoke PASS`
- `measure-startup smoke PASS`

### Task 5: 运行完整验证并固化实施文档

**Files:**
- Verify: `docs\superpowers\plans\2026-04-29-copilot-cli-stabilization.md`
- Verify: `diagnostics\check-stable-boundary-smoke.ps1`
- Verify: `diagnostics\check-stable-config-smoke.ps1`
- Verify: `diagnostics\check-mcp-health-smoke.ps1`
- Verify: `diagnostics\check-mcp-health-default-paths-smoke.ps1`
- Verify: `diagnostics\check-mcp-health-remote-failure-smoke.ps1`
- Verify: `diagnostics\hook-resolution-smoke.ps1`
- Verify: `diagnostics\hook-metrics-smoke.ps1`
- Verify: `diagnostics\measure-startup-smoke.ps1`

- [ ] **Step 1: 跑完整 smoke 套件**

Run:
```powershell
Set-Location 'C:\Users\HP\.copilot'
powershell -ExecutionPolicy Bypass -File .\diagnostics\check-stable-boundary-smoke.ps1
powershell -ExecutionPolicy Bypass -File .\diagnostics\check-stable-config-smoke.ps1
powershell -ExecutionPolicy Bypass -File .\diagnostics\check-mcp-health-smoke.ps1
powershell -ExecutionPolicy Bypass -File .\diagnostics\check-mcp-health-default-paths-smoke.ps1
powershell -ExecutionPolicy Bypass -File .\diagnostics\check-mcp-health-remote-failure-smoke.ps1
powershell -ExecutionPolicy Bypass -File .\diagnostics\hook-resolution-smoke.ps1
powershell -ExecutionPolicy Bypass -File .\diagnostics\hook-metrics-smoke.ps1
powershell -ExecutionPolicy Bypass -File .\diagnostics\measure-startup-smoke.ps1
```

Expected: 所有 smoke PASS，没有新的路径错误、编码错误或运行态泄漏。

- [ ] **Step 2: 复查最终工作区**

Run:
```powershell
Set-Location 'C:\Users\HP\.copilot'
git --no-pager status --short
git --no-pager diff --stat
```

Expected: 只反映稳定化收口目标文件，不出现运行态数据和无意义噪音文件。

- [ ] **Step 3: 回读计划文档并确认最终状态一致**

Run:
```powershell
Set-Location 'C:\Users\HP\.copilot'
Get-Content .\docs\superpowers\plans\2026-04-29-copilot-cli-stabilization.md
```

Expected: 文档仍准确描述 Task 1-5 的执行顺序与验证入口；若无冲突，不额外改文档。
