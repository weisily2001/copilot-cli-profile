# 启动观测说明

## 指标日志

- 日志文件：`C:\Users\HP\.copilot\startup-metrics.jsonl`
- 观测脚本：`C:\Users\HP\.copilot\diagnostics\measure-startup.ps1`
- `totalMs` 只统计本次实际启用的启动探针耗时；默认覆盖登录缓存读取和项目上下文解析
- `phases.hookEndMs` 作为可选对照探针单独记录，不并入 `totalMs`
- 脚本支持用 `-HookStartPath` / `-HookEndPath` / `-MetricsPath` 注入测试探针，便于本地 smoke 隔离真实 hook 和真实观测日志

## 字段

- `totalMs`
- `phases.loginStateMs`
- `phases.projectContextMs`
- `phases.hookStartMs`
- `phases.hookEndMs`
- `phases.resolveProjectMs`
- `phases.writeMetadataMs`
- `loginState.hasCachedLogin`
- `loginState.lastLogin`
- `loginState.loginCheckTriggered`
- `diagnostics\inspect-login-state.ps1` 可单独输出 `lastLoginHost` / `lastLoginUser` / `trustedFolders`
- `projectContext.projectKey`
- `projectContext.projectRoot`
- `projectContext.projectMemoryRestoreTriggered`

## Hook 阶段指标

- 日志文件：`C:\Users\HP\.copilot\hook-metrics.jsonl`
- 环境变量：
  - `COPILOT_ECC_MEMORY_METRICS_PATH`
  - `COPILOT_ECC_MEMORY_METRICS_KEEP_LAST`
  - `COPILOT_ECC_MEMORY_PROJECTS_ROOT`
  - `COPILOT_ECC_MEMORY_CACHE_PATH`
- 每条记录至少包含：
  - `timestamp`
  - `event`
  - `resolveProjectMs`
  - `writeMetadataMs`
  - `status`
- 成功记录额外包含：
  - `projectKey`
  - `projectRoot`
- 失败记录额外包含：
  - `currentPath`
  - `error`
- 默认仅保留最近 100 条记录，便于轻量排查且避免无限增长

其中：

- `loginState.loginCheckTriggered` 表示本次观测已执行登录缓存检查
- `projectContext.projectMemoryRestoreTriggered` 当前保持为 `false`，表示本脚本尚未执行项目记忆正文恢复，只记录项目上下文是否可解析

## 使用方式

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\HP\.copilot\diagnostics\measure-startup.ps1" -Runs 3
```

脚本会输出一条 JSON，并把每次结果追加到 JSONL 日志中，便于后续对比启动阶段耗时、当前项目上下文以及登录缓存状态。       
默认运行时，脚本会执行真实的 `session-start` / `session-end` hook，并从 `hook-metrics.jsonl` 汇总最近一次 hook 阶段指标。
`sessionStart` / `sessionEnd` 的 hook timeout 已收紧到 3 秒。
显式传入 `-HookStartPath` 或 `-HookEndPath` 时，可改用测试探针覆盖真实 hook。
只有在显式传入测试 hook 路径和测试 metrics 路径时，才会同时隔离真实 hook 与真实观测日志。

## 相关文档

- `C:\Users\HP\.copilot\mcp-observability.md`：MCP 健康检查脚本、输出字段与状态定义
- `C:\Users\HP\.copilot\README.md`：Profile 分层与诊断入口总览

## 保留策略

- 默认只保留最近 100 条记录
- 日志仅用于启动诊断
- 默认不写入项目记忆目录
