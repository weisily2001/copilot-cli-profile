# Copilot CLI Profile / MCP / LSP 治理升级设计

## 1. 目标

在现有全局行为内核、记忆治理、启动观测和多 agent 编排基础上，补齐 Copilot CLI 的三项运行治理能力：

1. Profile 化配置
2. MCP 健康检查与降级
3. LSP 能力扩容

本轮目标不是引入更复杂的自动化系统，而是让当前已经较完整的 Copilot CLI 全局配置从“功能齐全”升级到“按场景可切换、依赖异常时可诊断、语言支持更完整”的稳定形态。

## 2. 范围

本轮只覆盖以下内容：

- 定义 `default` / `research` / `heavy` 三档 profile
- 为 profile 建立 MCP / LSP 绑定关系
- 增加 MCP 健康检查脚本与健康规则文件
- 形成 MCP 降级建议机制
- 扩充 `lsp-config.json` 支持更多常用语言
- 更新全局文档，明确切换方式、诊断方式和回滚方式

本轮不覆盖：

- 自动后台守护式 profile 切换
- 自动修改真实登录态
- 自动删除或重写现有 MCP 配置
- 复杂评分引擎或持续自治调度

## 3. 现状结论

当前已经具备的基础能力：

1. 全局工作内核与治理规则已经稳定存在于 `copilot-instructions.md`
2. 已有本地 MCP：`memory`、`sequential-thinking`、`playwright`
3. 已有远程 MCP：`context7`、`exa`
4. 已有基础 LSP：`typescript`、`python`
5. 已有启动观测和多 agent 编排观测文档与脚本

因此本轮不需要重建基础设施，而是需要补齐三类治理缺口：

1. 能力缺少场景化分层
2. MCP 可用性缺少统一诊断和降级规则
3. LSP 仅覆盖部分常用语言

## 4. 设计原则

1. 不推翻已有全局配置结构，只做增量治理
2. 不把“诊断层”与“真实配置层”混为一体
3. 先保证可观测和可回滚，再追求自动化
4. Profile 负责表达场景，不负责隐藏真实配置
5. MCP 异常时显式降级，不静默吞错
6. LSP 扩容优先围绕常用语言栈，避免无边界堆叠

## 5. 总体架构

本轮采用“主配置保持稳定 + 场景分层 + 诊断建议层”的结构。

### 5.1 Profile 层

新增一份轻量 profile 配置，用于声明不同使用场景下建议启用的能力组合：

- `default`
- `research`
- `heavy`

每个 profile 至少描述：

- 说明文字
- 默认 MCP 组
- 默认 LSP 组
- 适用场景

Profile 的职责是定义推荐组合，不直接替代现有 `settings.json`、`mcp-config.json`、`lsp-config.json`。

### 5.2 MCP 治理层

在现有 MCP 配置之外新增一层治理能力，负责：

- 检查各 MCP 是否可达
- 记录检测耗时
- 输出失败原因
- 依据规则给出降级建议

该层不直接修改真实 MCP 配置，而是生成健康快照和建议动作，避免诊断逻辑污染稳定配置。

### 5.3 LSP 能力层

保留现有 `typescript` 与 `python`，并增补你常用语言栈所需的 LSP 条目。

LSP 能力层继续以 `lsp-config.json` 作为真实配置源，但通过 profile 配置表达“哪些 profile 推荐启用哪些语言”。

## 6. 文件设计

### 6.1 新增文件

建议新增以下文件：

- `C:\Users\HP\.copilot\profiles.json`
- `C:\Users\HP\.copilot\mcp-health-rules.json`
- `C:\Users\HP\.copilot\mcp-health.json`
- `C:\Users\HP\.copilot\diagnostics\check-mcp-health.ps1`
- `C:\Users\HP\.copilot\2026-04-27-copilot-cli-profile-mcp-lsp-v1-implementation-plan.md`

说明：

- `profiles.json`：声明 profile 与能力组映射
- `mcp-health-rules.json`：定义检测目标、超时和降级动作
- `mcp-health.json`：保存最近一次健康快照
- `check-mcp-health.ps1`：执行检查并生成结果
- 实施计划文档在设计通过后生成

### 6.2 更新文件

本轮预计更新：

- `C:\Users\HP\.copilot\README.md`
- `C:\Users\HP\.copilot\lsp-config.json`
- `C:\Users\HP\.copilot\startup-observability.md`

如需补充独立说明，也可新增一份：

- `C:\Users\HP\.copilot\mcp-observability.md`

## 7. Profile 设计

### 7.1 default

定位：日常开发与普通问答。

建议包含：

- 高频 MCP：`context7`
- 稳定本地 MCP：`memory`、`sequential-thinking`
- 高频 LSP：`typescript`、`python`

特点：

- 启动负担较低
- 适合大多数普通任务

### 7.2 research

定位：资料查询、设计、方案分析、文档查证。

建议包含：

- `context7`
- `exa`
- `memory`
- `sequential-thinking`

LSP 维持中等规模，优先保留当前活跃语言。

特点：

- 强化资料获取和推理
- 不默认追求最大全量工具

### 7.3 heavy

定位：复杂多阶段任务、重型排查、需要更多语言支持的场景。

建议包含：

- 全部稳定 MCP
- 扩展 LSP 语言集
- 更适合复杂实施和深度排查

特点：

- 功能最全
- 启动和诊断成本最高

## 8. MCP 健康检查与降级设计

### 8.1 检查目标

本轮检查以下 MCP：

- `context7`
- `exa`
- `memory`
- `sequential-thinking`
- `playwright`

### 8.2 输出字段

健康结果至少包含：

- `name`
- `type`
- `status`
- `latencyMs`
- `checkedAt`
- `error`
- `suggestedAction`

其中 `status` 只允许：

- `healthy`
- `degraded`
- `unavailable`

### 8.3 降级规则

规则文件中至少声明：

- 检测超时
- 失败后的建议动作
- 对应的替代 MCP 或替代工作流

示例规则：

1. `context7` 不可用：建议退回 `docs.github.com` 或本地文档
2. `exa` 不可用：建议关闭联网研究增强，仅保留官方文档查询
3. 本地 MCP 不可用：建议提示修复本地运行环境，不自动删除配置

### 8.4 核心边界

本轮只输出“建议降级”，不自动重写 `mcp-config.json`。  
这样可以避免脚本误操作破坏稳定配置，同时保留人工确认空间。

## 9. LSP 扩容设计

### 9.1 扩容原则

优先扩容到你实际常见的语言栈，避免为了“看起来完整”而无边界堆叠。

推荐优先级：

1. `json` / `yaml`
2. `go`
3. `java`
4. `rust`
5. `sql`

### 9.2 配置策略

保持 `lsp-config.json` 为真实配置文件。  
Profile 文件只记录哪些语言属于：

- 默认组
- 研究组
- 重型组

这样可以把“真实 LSP 定义”和“按场景启用建议”拆开管理。

## 10. 数据流

本轮数据流如下：

1. 读取 `profiles.json`
2. 根据 profile 确定推荐 MCP / LSP 组合
3. 运行 `check-mcp-health.ps1`
4. 根据 `mcp-health-rules.json` 生成检查结果
5. 输出到 `mcp-health.json`
6. 用户根据诊断结果决定是否切换 profile 或执行降级动作

这里的关键是：

- Profile 决定“推荐组合”
- 健康脚本决定“当前状态”
- 用户或后续流程决定“是否切换”

三者职责分离，不互相覆盖。

## 11. 错误处理

1. MCP 检查失败时必须写出明确错误，不静默吞掉
2. 任一 MCP 不可达时，不自动删除现有配置
3. Profile 引用到不可用 MCP / LSP 时，保留 profile 定义，同时在健康结果中标注风险
4. LSP 扩容后若本机缺少对应 language server，不回退现有语言配置，只提示缺失项

## 12. 验收标准

本轮完成后应满足：

1. 能清楚列出 3 个 profile 及其能力映射
2. MCP 健康脚本可输出结构化结果
3. 结构化结果能标识状态、耗时、失败原因和建议动作
4. `lsp-config.json` 完成扩容，且不破坏现有 `typescript` / `python`
5. `README.md` 明确说明切换、诊断与回滚方式

## 13. 风险与约束

### 13.1 风险

1. Profile 设计过重，反而增加维护面
2. MCP 健康检查过于激进，导致误报
3. LSP 扩容过多，导致本机环境准备成本抬高

### 13.2 控制方式

1. Profile 只做 3 档，不继续扩张
2. 健康脚本先覆盖已有 MCP，不引入无关检查项
3. LSP 先扩到高频语言，不做低频语言堆叠
4. 诊断层不直接改真实配置，始终保留手动回滚空间

## 14. 推荐实施顺序

1. 先落地 `profiles.json`
2. 再补 MCP 健康规则与检查脚本
3. 然后扩充 `lsp-config.json`
4. 最后更新文档与回滚说明

## 15. 本轮结论

本轮推荐采用：

- **方案 B：Profile 分层 + MCP 健康检查与降级 + LSP 定向扩容**

这是当前最适合你现有 Copilot CLI 体系的升级路径：  
它既延续了现有治理结构，又把真正影响长期使用体验的三块短板补齐到了可维护的 v1 水位。
