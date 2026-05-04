---
name: preference-learning
description: 当用户明确表达稳定偏好或纠正既有做法时，将规则写入全局偏好层或纠错学习层。
---

使用该技能时：
1. 先判断这是稳定偏好还是一次性要求。
2. 每天新增记忆默认先视为短期任务记忆，不直接写入长期层。
3. 只有稳定偏好、明确纠错或可跨会话复用的项目长期知识，才允许升级写入长期层。
4. 稳定偏好写入 `C:\Users\HP\.copilot\memory\global\profile.md` 或 `preferences.json`。
5. 明确纠错写入 `C:\Users\HP\.copilot\memory\global\corrections.md`。
6. 不把项目正式文档写入运行时项目记忆目录。
7. 稳定偏好或明确纠错写入长期层后，同步刷新 `C:\Users\HP\.copilot\memory\global\memory-index.md`，确保后续任务先命中索引。
