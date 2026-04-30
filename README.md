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

## 稳定使用建议

- 日常默认使用 `default`
- 做资料查证、方案分析和文档研究时使用 `research`
- `heavy` 只在复杂多阶段任务时按需启用，不作为日常默认面
- 以下文件属于运行态或本机态，不纳入稳定主线：`config.json`、`permissions-config.json`、`hook-metrics.jsonl`、`startup-metrics.jsonl`、`mcp-health.json`

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