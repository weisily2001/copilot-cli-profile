# 全局记忆索引

## 高频入口

- 稳定偏好 -> `memory\global\profile.md` -> 先看口语化偏好摘要
- 结构化偏好 -> `memory\global\preferences.json` -> 机器可读键值优先
- 稳定纠错 -> `memory\global\corrections.md` -> 先看触发场景与避免事项
- 全局稳定事实 -> `memory\global\global-facts.md` -> 只保留长期有效事实

## 技能入口

- `ecc-verification-before-completion` -> skills\ecc-verification-before-completion\SKILL.md -> 在宣称任务完成前回读目标、核对改动面并说明实际结果。
- `memory-handoff` -> skills\memory-handoff\SKILL.md -> 在任务结束或窗口切换前压缩项目记忆并维护 handoff/state/decisions。
- `parallel-orchestration` -> skills\parallel-orchestration\SKILL.md -> 在复杂任务执行前决定是否并行、如何拆分子任务和如何收敛。
- `preference-learning` -> skills\preference-learning\SKILL.md -> 在用户明确表达稳定偏好或纠错时，把规则升级到全局长期层。
- `research-first` -> skills\research-first\SKILL.md -> 实现前先研究目录、关键文件、已有模式和外部文档。
