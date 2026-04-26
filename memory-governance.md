# Copilot CLI 文档与记忆治理

## 全局文档

- 路径：`C:\Users\HP\.copilot`
- 范围：Copilot CLI 全局能力、全局配置、全局方法说明、全局设计文档

## 项目正式文档

- 路径：`E:\copilotcli\<项目名>`
- 范围：需求、设计、计划、验证、复盘、交付说明

## 运行时项目记忆

- 路径：`C:\Users\HP\.copilot\memory\projects\<project-id>`
- 范围：`handoff.md`、`state.md`、`decisions.md`、`overview.md`、`project.json`、`last-session.json`
- 规则：
  - `decisions.md` / `overview.md` 用于长期知识恢复；恢复时读取存在的文件，不要求二者同时存在
  - `project.json` / `last-session.json` 是 hook 维护的运行时元数据文件，用于项目根与最近会话信息，不属于正式文档，也不代替长期知识文件
  - 运行时元数据文件属于合法项目记忆文件，不按越界文件或清理目标处理
  - 只放恢复上下文需要的轻量记忆与元数据，不放项目正式长文档
