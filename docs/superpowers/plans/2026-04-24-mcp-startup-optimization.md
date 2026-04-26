# MCP 启动提速实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将远程 MCP 从默认启动配置中拆出，保留按需启用能力，同时减少日常启动等待。

**Architecture:** 保留 `C:\Users\HP\.copilot\mcp-config.json` 作为默认配置，仅承载本地 MCP。新增 `C:\Users\HP\.copilot\mcp-config.remote.json` 保存 `exa` 与 `context7`，使远程 MCP 不参与默认启动。实施后通过读取配置和实际启动验证默认配置不再包含远程 MCP。

**Tech Stack:** GitHub Copilot CLI 配置文件、JSON、PowerShell

---

### Task 1: 拆分默认与远程 MCP 配置

**Files:**
- Create: `C:\Users\HP\.copilot\mcp-config.remote.json`
- Modify: `C:\Users\HP\.copilot\mcp-config.json`
- Test: `C:\Users\HP\.copilot\mcp-config.json`, `C:\Users\HP\.copilot\mcp-config.remote.json`

- [ ] **Step 1: 先读取当前配置，确认远程 MCP 现状**

```powershell
Get-Content 'C:\Users\HP\.copilot\mcp-config.json'
```

- [ ] **Step 2: 运行一次结构检查，确认当前 `exa` 与 `context7` 都在默认配置里**

Run:
```powershell
$json = Get-Content 'C:\Users\HP\.copilot\mcp-config.json' -Raw | ConvertFrom-Json
$json.mcpServers.PSObject.Properties.Name
```
Expected: 输出中包含 `exa` 和 `context7`

- [ ] **Step 3: 新建远程 MCP 备用配置文件**

```json
{
  "mcpServers": {
    "exa": {
      "type": "http",
      "url": "https://mcp.exa.ai/mcp",
      "headers": {},
      "tools": [
        "*"
      ]
    },
    "context7": {
      "type": "http",
      "url": "https://mcp.context7.com/mcp",
      "headers": {},
      "tools": [
        "*"
      ]
    }
  }
}
```

- [ ] **Step 4: 精简默认配置，只保留本地 MCP**

```json
{
  "mcpServers": {
    "memory": {
      "type": "local",
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-memory@2026.1.26"
      ],
      "env": {},
      "tools": [
        "*"
      ]
    },
    "sequential-thinking": {
      "type": "local",
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-sequential-thinking@2025.12.18"
      ],
      "env": {},
      "tools": [
        "*"
      ]
    },
    "playwright": {
      "type": "local",
      "command": "npx",
      "args": [
        "-y",
        "@playwright/mcp@0.0.69"
      ],
      "env": {},
      "tools": [
        "*"
      ]
    }
  }
}
```

- [ ] **Step 5: 重新读取两个配置文件，确认拆分结果正确**

Run:
```powershell
$default = Get-Content 'C:\Users\HP\.copilot\mcp-config.json' -Raw | ConvertFrom-Json
$remote = Get-Content 'C:\Users\HP\.copilot\mcp-config.remote.json' -Raw | ConvertFrom-Json
'default=' + (($default.mcpServers.PSObject.Properties.Name) -join ',')
'remote=' + (($remote.mcpServers.PSObject.Properties.Name) -join ',')
```
Expected:
- `default=` 只包含 `memory,sequential-thinking,playwright`
- `remote=` 只包含 `exa,context7`

### Task 2: 验证默认启动路径

**Files:**
- Modify: `C:\Users\HP\.copilot\mcp-config.json`
- Test: `C:\Users\HP\.copilot\session-state\`

- [ ] **Step 1: 启动 Copilot CLI，使用默认配置进入新会话**

Run:
```powershell
copilot
```
Expected: 会话正常启动，不再默认尝试连接远程 MCP

- [ ] **Step 2: 在新会话中检查 MCP 列表**

Run:
```text
/mcp show
```
Expected: 默认列表中只出现本地 MCP，或至少不再主动连接 `exa`、`context7`

- [ ] **Step 3: 关闭会话后检查最新事件日志是否仍出现远程 MCP 启动等待**

Run:
```powershell
Get-ChildItem 'C:\Users\HP\.copilot\session-state' -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
```

然后运行：

```powershell
Select-String -Path '<latest-session>\events.jsonl' -Pattern "taking longer than expected to connect|exa|context7"
```

Expected: 不再出现默认启动时连接 `exa`、`context7` 的同类等待告警

- [ ] **Step 4: 记录备用远程配置的启用方式**

```text
需要远程能力时，将 `C:\Users\HP\.copilot\mcp-config.remote.json` 中的 `mcpServers` 条目合并回 `C:\Users\HP\.copilot\mcp-config.json`，然后重启 Copilot CLI。
```

- [ ] **Step 5: 完成后再次读取两个配置文件，作为最终交付核对**

Run:
```powershell
Get-Content 'C:\Users\HP\.copilot\mcp-config.json'
Get-Content 'C:\Users\HP\.copilot\mcp-config.remote.json'
```
Expected: 默认配置和远程备用配置内容分别与设计一致
