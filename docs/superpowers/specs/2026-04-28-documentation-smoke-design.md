# 文档检查 Smoke 设计

## 1. 目标

为 `.copilot` 仓库新增一个可重复运行的文档检查 smoke，替代此前零散的内联 PowerShell 文档断言命令。

本次只解决“README / startup-observability / mcp-observability 三份文档是否仍与当前实现对齐”的问题，不扩大到所有文档，也不引入新的测试框架。

## 2. 范围

本次纳入：

1. 新增独立脚本 `diagnostics\check-documentation-smoke.ps1`
2. 检查以下 3 份文档：
   - `README.md`
   - `startup-observability.md`
   - `mcp-observability.md`
3. 校验文档中的最小关键断言

本次不纳入：

1. 所有 Markdown 文档的通用 lint
2. 外链可达性检查
3. 自动修正文档内容
4. 与实现无关的格式检查

## 3. 现状

当前仓库已有多条 diagnostics smoke，例如：

1. `diagnostics\inspect-profiles-smoke.ps1`
2. `diagnostics\check-mcp-health-smoke.ps1`
3. `diagnostics\measure-startup-smoke.ps1`

但文档一致性检查仍依赖手写内联 PowerShell，在以下场景不够稳定：

1. 复跑时容易敲错
2. 不能像其他 smoke 一样被直接调用
3. 后续集成时不利于统一验证

## 4. 设计决策

### 4.1 采用独立 smoke 脚本

本次新增单独的 `diagnostics\check-documentation-smoke.ps1`，而不是把文档断言塞进 `inspect-profiles-smoke.ps1` 或 `check-mcp-health-smoke.ps1`。

原因：

1. 文档错误应与功能错误分开定位
2. diagnostics 目录已有“一个主题一个 smoke”的模式
3. 后续若扩展更多文档断言，不会污染功能 smoke

### 4.2 只检查最小关键断言

脚本只断言当前最关键、最容易回归的文档事实：

1. `README.md` 必须提到 `profiles.json`
2. `README.md` 必须提到 `check-mcp-health.ps1`
3. `README.md` 必须说明默认输出到当前仓库根目录下的 `mcp-health.json`
4. `startup-observability.md` 必须提到 `mcp-observability.md`
5. `mcp-observability.md` 必须存在
6. `mcp-observability.md` 必须说明默认输出到当前仓库根目录下的 `mcp-health.json`

这样可以保证脚本足够稳定，不因为文案小改就频繁误报。

### 4.3 不依赖外部工具

脚本继续使用 PowerShell 原生能力：

1. `Get-Content -Raw -Encoding UTF8`
2. `[regex]::Escape(...)`
3. `throw` 明确失败
4. `Write-Host 'documentation smoke PASS'` 输出通过标记

这样与现有 smoke 风格一致，也不额外增加环境依赖。

## 5. 文件变更

### 新增

1. `C:\Users\HP\.copilot\diagnostics\check-documentation-smoke.ps1`

### 不改动

1. `README.md`
2. `startup-observability.md`
3. `mcp-observability.md`

除非实现过程中发现当前已合并的文档内容与设计断言仍不一致，否则本轮不再改动文档正文。

## 6. 脚本行为

脚本执行时应：

1. 读取仓库根目录下的三份文档
2. 逐项执行断言
3. 任一断言失败时立即抛错并中止
4. 全部通过时输出：

```powershell
documentation smoke PASS
```

## 7. 验证方式

本轮验收至少包含：

1. 单独运行 `diagnostics\check-documentation-smoke.ps1`
2. 联动运行：
   - `diagnostics\inspect-profiles-smoke.ps1`
   - `diagnostics\check-mcp-health-smoke.ps1`
   - `diagnostics\check-documentation-smoke.ps1`

预期结果：

1. 三个脚本均 PASS
2. 不产生新的运行时产物
3. 不修改任何现有文档内容

## 8. 风险与控制

### 风险

1. 文档断言写得过细，后续正常措辞调整也会误报
2. 脚本路径写死错误，导致在非标准工作区运行失败

### 控制

1. 断言只覆盖稳定关键词，不检查整段文案
2. 使用脚本所在仓库根目录相对路径读取文档，不依赖外部环境变量

## 9. 结论

本次推荐采用：

**独立 `check-documentation-smoke.ps1` + 最小关键断言**

这是当前最小、最稳、最符合现有 diagnostics 模式的方案。
