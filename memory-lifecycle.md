# Copilot CLI 记忆生命周期规则

## 1. 分层
- 长期偏好层
- 项目长期知识层
- 短期任务状态层
- 纠错学习层

## 2. 分流
- 新增记忆默认先进入短期任务状态层
- 只有稳定偏好、明确纠错、可复用项目长期知识才能升级为长期层

## 3. 压缩
- 任务完成前触发
- 窗口切换前触发
- 用户要求“明天继续”时触发
- 内容明显膨胀时触发
- 压缩后只保留：当前目标、当前阶段、已完成项、下一步、阻塞点、必要引用路径
- 若项目记忆文件已启用且存在 `C:\Users\HP\.copilot\memory\projects\<project-id>\handoff.md`，则将压缩后的可交接摘要写入并更新该文件
- 若项目记忆文件已启用且存在 `C:\Users\HP\.copilot\memory\projects\<project-id>\state.md`，则将压缩后的当前状态摘要写入并更新该文件
- 若 `handoff.md` 与 `state.md` 都不存在，仅提示可在 `C:\Users\HP\.copilot\memory\projects\<project-id>\` 下启用 `handoff.md` / `state.md`；不自动创建
- 压缩后的短期任务摘要在未启用项目记忆文件时，仅保留在当前短期层，不触发自动建文件
- `handoff.md` 负责可交接的简短上下文与下一步，`state.md` 负责当前状态、进度、阻塞点与最近决策

## 4. 清理
- 压缩后自动清理无复用价值内容
- 冗长过程描述、重复信息、临时调试记录默认删除

## 5. 升级判断
- 稳定偏好 → `C:\Users\HP\.copilot\memory\global\profile.md` 或 `C:\Users\HP\.copilot\memory\global\preferences.json`
- 明确纠错 → `C:\Users\HP\.copilot\memory\global\corrections.md`
- 项目长期知识 → `C:\Users\HP\.copilot\memory\projects\<project-id>\decisions.md` 或 `C:\Users\HP\.copilot\memory\projects\<project-id>\overview.md`
