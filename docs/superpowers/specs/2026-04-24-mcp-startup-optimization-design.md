# Copilot CLI MCP 启动提速设计

## 问题

当前 `C:\Users\HP\.copilot\mcp-config.json` 默认同时加载本地 MCP 与远程 MCP。已观察到 `exa`、`context7` 在会话启动阶段出现连接变慢告警，导致日常启动体验变差。用户希望保留远程能力，但改为按需启用，而不是每次启动都默认连接。

## 目标

- 默认启动时不连接远程 MCP，缩短常规会话进入时间
- 保留 `exa` 与 `context7` 的配置，便于需要联网研究时恢复
- 本次只调整 MCP 配置分层，不改登录逻辑，不改 hooks，不改其他全局行为

## 方案

### 默认配置

保留 `mcp-config.json` 作为默认配置文件，仅包含本地 MCP：

- `memory`
- `sequential-thinking`
- `playwright`

这样默认启动路径只涉及本地进程，不再等待远程 MCP 握手。

### 备用远程配置

新增 `mcp-config.remote.json`，保存远程 MCP：

- `exa`
- `context7`

该文件不参与默认启动，仅作为备用配置保留。需要联网搜索或官方文档查询时，再手动合并或切换回主配置。

## 操作方式

- 日常使用：保持默认配置，不加载远程 MCP
- 需要远程能力时：把备用远程配置中的服务合并回 `mcp-config.json`，或临时替换为含远程 MCP 的配置后重启会话

## 风险与边界

- 优点：默认启动更快，远程连接问题不再阻塞普通会话
- 代价：需要 `exa` / `context7` 时要多一步手动切换
- 边界：本次不处理 OAuth 登录重复问题；该问题单独诊断

## 验证标准

- 默认配置下，`mcp-config.json` 不再包含 `exa`、`context7`
- 备用文件中完整保留 `exa`、`context7` 定义
- 修改后启动不会再因为默认连接远程 MCP 而产生同类等待
