# MCP 健康观测说明

## 脚本

- `C:\Users\HP\.copilot\diagnostics\check-mcp-health.ps1`
- `C:\Users\HP\.copilot\diagnostics\check-mcp-health-smoke.ps1`
- `C:\Users\HP\.copilot\diagnostics\check-mcp-health-default-paths-smoke.ps1`
- `C:\Users\HP\.copilot\diagnostics\check-mcp-health-remote-failure-smoke.ps1`

## 输出文件

- 默认写入当前仓库根目录下的 `mcp-health.json`
- 标准部署到 `C:\Users\HP\.copilot` 时，输出文件位于 `C:\Users\HP\.copilot\mcp-health.json`

## 输出字段

- `generatedAt`
- `results[].name`
- `results[].type`
- `results[].status`
- `results[].latencyMs`
- `results[].checkedAt`
- `results[].error`
- `results[].suggestedAction`

## 状态含义

- `healthy`：当前检查通过
- `degraded`：当前可继续使用，但建议降级或补做联网探测
- `unavailable`：当前不可用，应先修复

## 使用方式

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\HP\.copilot\diagnostics\check-mcp-health.ps1"
```

快速离线检查：

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\HP\.copilot\diagnostics\check-mcp-health.ps1" -SkipHttpProbe
```

## 说明

- 本轮只输出健康结果和建议动作，不自动改写 `mcp-config.json`
- 本地 MCP 命令缺失时会返回 `unavailable`
- 远程 MCP 在跳过 HTTP 探测时会返回 `degraded`
- 远程 MCP 实际探测失败时会返回 `unavailable`
