# 多 Agent 编排观测说明

## 调度评估脚本

- 脚本：`C:\Users\HP\.copilot\diagnostics\evaluate-agent-orchestration.ps1`
- 烟雾测试：`C:\Users\HP\.copilot\diagnostics\evaluate-agent-orchestration-smoke.ps1`

## 输出字段

- `mode`
- `budgetTier`
- `maxAgents`
- `stopConditions`
- `reasons`

## 推荐验收指标

- 总耗时
- 总 token 成本
- 重复工作率
- 一次性交付率

## 使用方式

```powershell
$scenario = @{
  goal = '并行研究三个独立模块'
  independentSubtasks = 3
  phaseCount = 1
  sharedState = 'low'
  estimatedContextSize = 'medium'
  userIntentClear = $true
} | ConvertTo-Json -Depth 3

powershell -ExecutionPolicy Bypass -File "C:\Users\HP\.copilot\diagnostics\evaluate-agent-orchestration.ps1" -ScenarioJson $scenario
```
