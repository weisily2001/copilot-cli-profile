---
applyTo: "**"
---

当处理当前项目的正式文档时：
1. 项目正式文档默认写入 `E:\copilotcli` 下与当前项目同名的目录。
2. 不把项目正式长文档写入 `C:\Users\HP\.copilot\memory\projects` 下当前项目对应的记忆目录。
3. 项目记忆目录只保留 `handoff.md`、`state.md`、`decisions.md`、`overview.md` 等轻量记忆文件，以及 `project.json`、`last-session.json` 等 hook 维护的运行时元数据文件。
4. `decisions.md` / `overview.md` 用于长期知识恢复；`project.json` / `last-session.json` 仅用于 hook 维护项目根与最近会话元数据，不把 `decisions.md` 描述成 hook 的项目根来源。
