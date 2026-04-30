# 当前状态

- 当前阶段：稳定化与清理收口。
- 已完成能力：全局内核、双层记忆层与 session hooks、MCP/LSP 基线、技能与代理、多 Agent 编排 v1、profile 与 hook metrics 基线修复。
- 当前待做清理面：压缩全局偏好与项目记忆到稳定摘要，删除 `mcp-health.json`、`startup-metrics.jsonl`、`hook-metrics.jsonl` 等实际运行产物，确保工作区只剩可提交的稳定改动。
- 验证入口：`git --no-pager status --short`，回读 5 个记忆文件，确认运行产物删除结果。
