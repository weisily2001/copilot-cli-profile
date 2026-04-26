# 长期决策

- 采用双层记忆：全局偏好 + 项目状态/知识
- 优先使用 Copilot CLI 原生表面
- 仅将轻量自动化交给 hooks
- 为避免与现有技能冲突，个人技能 `verification-before-completion` 改名为 `ecc-verification-before-completion`
- 项目记忆模板采用条件式规则：只有相关记忆文件存在时才读取或更新，避免模板对新项目产生强依赖
- `C:\Users\HP\.copilot` 已初始化为本地 Git 仓库，便于后续用 worktree 管理全局配置演进
- 多 Agent 编排 v1 采用“评估脚本 + 技能 + 代理 + 全局指令 + 模板规则”组合落地，不改 Copilot 本体
- hooks metrics 的 `error` 字段改为稳定摘要，控制台仍保留原始异常，避免 JSONL 因本地化异常文本失稳
