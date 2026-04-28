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

## Profile 分层

- `profiles.json` 定义 `default`、`research`、`heavy` 三档能力组合
- `default` 适合日常开发与普通问答
- `research` 强化资料查询、设计分析和文档查证
- `heavy` 适合复杂多阶段任务与更完整的语言支持
- 可通过 `diagnostics\inspect-profiles.ps1` 查看 profile 与 MCP / LSP 引用是否一致

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\HP\.copilot\diagnostics\inspect-profiles.ps1"
```

## MCP 健康诊断

运行：

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\HP\.copilot\diagnostics\check-mcp-health.ps1"
```

输出：

- 结构化结果会打印到终端
- 默认写入当前仓库根目录下的 `mcp-health.json`
- 标准部署到 `C:\Users\HP\.copilot` 时，输出文件位于 `C:\Users\HP\.copilot\mcp-health.json`
- 使用 `-SkipHttpProbe` 时，远程 MCP 会以 `degraded` 返回，便于离线或快速检查

更多字段说明见 `C:\Users\HP\.copilot\mcp-observability.md`。

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
