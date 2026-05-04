---
name: memory-handoff
description: 在任务结束或窗口切换前整理项目记忆目录下的 handoff.md、state.md 和 decisions.md，确保跨窗口连续性。
---

使用该技能时：
1. 先基于当前项目定位 `C:\Users\HP\.copilot\memory\projects\<project-id>`。
2. 若该目录下已存在 `handoff.md`，则读取并更新；若已存在 `state.md`，则读取并更新；若二者都不存在，仅提示可在该目录启用，不自动创建。
3. 先把稳定偏好升级到 `profile.md` / `preferences.json`，把明确纠错升级到 `corrections.md`，再处理项目长期知识。
4. 项目长期知识分流：仅在项目记忆文件已启用时，按需更新既有的 `decisions.md` / `overview.md`；若尚未启用，仅提示可在该目录启用对应文件，不自动创建。
5. 将 `handoff.md` 保持为单屏可读摘要。
6. 在任务结束、窗口切换或用户要求跨天续做前，先把短期任务状态压缩为单屏摘要；若 `handoff.md` 已存在则更新 `handoff.md`，若 `state.md` 已存在则更新 `state.md`，若二者都不存在则仅提示可选位置，不因压缩而自动建文件；压缩后再判断长期保留价值。
7. 无长期价值的过程性内容进行清理，只保留当前状态、下一步、阻塞点、必要引用路径。
8. 不将项目正式文档、长设计文档或实施计划写入项目记忆目录；这些正式文档应写入约定的项目文档目录。
9. 若全局长期层发生变化，任务收尾前同步刷新 `C:\Users\HP\.copilot\memory\global\memory-index.md` 与 `C:\Users\HP\.copilot\skills\skill-registry.json`。
