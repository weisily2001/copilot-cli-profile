# Copilot CLI 记忆闭环 v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 Copilot CLI 建立可持续的记忆闭环 v2：明确文档落盘边界、补齐全局偏好与纠错学习层，并把规则固化到全局指令与项目模板中。

**Architecture:** 实现分 4 层推进。先固化“全局文档 / 项目正式文档 / 运行时项目记忆”的边界，再补齐全局记忆层中的纠错学习文件与读取规则，然后加入专门的偏好学习技能，最后把项目模板同步到新规则并做端到端验证。整个方案延续现有轻量 hooks，不把长文档写入运行时记忆目录。

**Tech Stack:** Markdown 指令与技能文件、JSON 偏好文件、PowerShell 校验命令、Copilot CLI 交互验证

---

## File Structure

- Modify: `C:\Users\HP\.copilot\copilot-instructions.md` — 固化全局文档治理与记忆闭环 v2 的顶层规则
- Create: `C:\Users\HP\.copilot\memory-governance.md` — 说明全局文档、项目文档、运行时记忆的边界
- Modify: `C:\Users\HP\.copilot\memory\global\profile.md` — 补充用户长期偏好与纠错写入规则
- Modify: `C:\Users\HP\.copilot\memory\global\preferences.json` — 增加记忆闭环 v2 相关键
- Create: `C:\Users\HP\.copilot\memory\global\corrections.md` — 存放稳定纠错与避免重复犯错的规则
- Create: `C:\Users\HP\.copilot\skills\preference-learning\SKILL.md` — 在用户纠正或明确偏好时指导如何写入全局记忆
- Modify: `C:\Users\HP\.copilot\skills\memory-handoff\SKILL.md` — 保持项目记忆轻量，不混入项目正式文档
- Modify: `C:\Users\HP\.copilot\templates\project-bootstrap\.github\copilot-instructions.md` — 告知项目正式文档默认落在 `E:\copilotcli\<项目名>`
- Modify: `C:\Users\HP\.copilot\templates\project-bootstrap\.github\instructions\memory-hydration.instructions.md` — 继续只读取轻量记忆文件
- Create: `C:\Users\HP\.copilot\templates\project-bootstrap\.github\instructions\document-placement.instructions.md` — 在项目模板中声明文档落盘规则
- Modify: `C:\Users\HP\Desktop\copilot-ecc-bootstrap-test\.github\copilot-instructions.md` — 用于验证模板同步结果
- Modify: `C:\Users\HP\Desktop\copilot-ecc-bootstrap-test\.github\instructions\memory-hydration.instructions.md` — 用于验证模板同步结果
- Create: `C:\Users\HP\Desktop\copilot-ecc-bootstrap-test\.github\instructions\document-placement.instructions.md` — 用于验证模板同步结果

### Task 1: 固化全局文档治理规则

**Files:**
- Create: `C:\Users\HP\.copilot\memory-governance.md`
- Modify: `C:\Users\HP\.copilot\copilot-instructions.md`

- [ ] **Step 1: 写一个会失败的治理规则检查**

Run:

```powershell
$checks = @(
  Select-String -Path "C:\Users\HP\.copilot\copilot-instructions.md" -Pattern "全局能力、全局配置、全局流程"
  Select-String -Path "C:\Users\HP\.copilot\copilot-instructions.md" -Pattern "E:\\copilotcli\\<项目名>"
  Test-Path "C:\Users\HP\.copilot\memory-governance.md"
)
$checks
```

Expected: 至少一个检查为空或 `False`，说明规则尚未完整落地。

- [ ] **Step 2: 创建治理说明文档**

Create `C:\Users\HP\.copilot\memory-governance.md` with:

```md
# Copilot CLI 文档与记忆治理

## 全局文档

- 路径：`C:\Users\HP\.copilot`
- 范围：Copilot CLI 全局能力、全局配置、全局方法说明、全局设计文档

## 项目正式文档

- 路径：`E:\copilotcli\<项目名>`
- 范围：需求、设计、计划、验证、复盘、交付说明

## 运行时项目记忆

- 路径：`C:\Users\HP\.copilot\memory\projects\<project-id>`
- 范围：`handoff.md`、`state.md`、`decisions.md`、`overview.md`
- 规则：只放恢复上下文需要的短记忆，不放项目正式长文档
```

- [ ] **Step 3: 最小化修改全局工作内核**

在 `C:\Users\HP\.copilot\copilot-instructions.md` 中追加以下规则：

```md
9. 有关 Copilot CLI 全局能力、全局配置、全局流程的文档，统一写入 `C:\Users\HP\.copilot`。
10. 有关具体项目的设计、计划、验证、复盘文档，统一写入 `E:\copilotcli\<项目名>`。
11. `C:\Users\HP\.copilot\memory\projects\<project-id>` 仅用于运行时项目记忆，不作为项目正式文档目录。
```

- [ ] **Step 4: 重新运行治理规则检查，确认通过**

Run:

```powershell
$checks = @(
  Select-String -Path "C:\Users\HP\.copilot\copilot-instructions.md" -Pattern "全局能力、全局配置、全局流程"
  Select-String -Path "C:\Users\HP\.copilot\copilot-instructions.md" -Pattern "E:\\copilotcli\\<项目名>"
  Test-Path "C:\Users\HP\.copilot\memory-governance.md"
)
$checks
```

Expected: 三项都能返回匹配或 `True`。

- [ ] **Step 5: 记录当前目录不执行提交**

Run:

```powershell
git -C "C:\Users\HP\.copilot" rev-parse --is-inside-work-tree
```

Expected: 非零退出或报错，记录“目标目录不是 Git 仓库，因此本轮不提交”。

### Task 2: 补齐全局记忆闭环 v2 的偏好层与纠错层

**Files:**
- Modify: `C:\Users\HP\.copilot\memory\global\profile.md`
- Modify: `C:\Users\HP\.copilot\memory\global\preferences.json`
- Create: `C:\Users\HP\.copilot\memory\global\corrections.md`

- [ ] **Step 1: 写一个会失败的全局记忆层检查**

Run:

```powershell
$checks = [pscustomobject]@{
  HasCorrectionsFile = Test-Path "C:\Users\HP\.copilot\memory\global\corrections.md"
  HasCorrectionKey = Select-String -Path "C:\Users\HP\.copilot\memory\global\preferences.json" -Pattern '"correctionLearning"'
  HasLearningRule = Select-String -Path "C:\Users\HP\.copilot\memory\global\profile.md" -Pattern "纠错"
}
$checks
```

Expected: 至少一项缺失。

- [ ] **Step 2: 创建纠错学习文件**

Create `C:\Users\HP\.copilot\memory\global\corrections.md` with:

```md
# 全局纠错学习

## 写入条件

- 用户明确说“不是这个意思”
- 用户明确要求“以后都这样做”
- 同类误判重复出现两次及以上

## 写入规则

- 只记录稳定规则，不记录一次性临时偏好
- 每条记录都要包含“触发场景、正确做法、避免事项”

## 当前稳定规则

- 暂无
```

- [ ] **Step 3: 扩展全局偏好文档与 JSON**

将 `C:\Users\HP\.copilot\memory\global\profile.md` 扩展为包含：

```md
# 用户全局偏好

- 偏好简洁、信息密度高的回答
- 遇到复杂任务先规划，再实施
- 优先保证跨窗口连续性
- 长期记忆分为：个人偏好、项目知识、当前任务状态、纠错学习
- 当用户明确纠正表达或流程时，优先写入全局纠错学习层
```

将 `C:\Users\HP\.copilot\memory\global\preferences.json` 扩展为：

```json
{
  "responseStyle": "concise",
  "planningPreference": "plan-first-for-complex-work",
  "memoryPriority": "cross-window-continuity",
  "memoryMode": "global-plus-project",
  "correctionLearning": "enabled",
  "documentGovernance": "global-in-copilot-home-project-docs-in-e-drive"
}
```

- [ ] **Step 4: 重新运行全局记忆层检查，确认通过**

Run:

```powershell
$checks = [pscustomobject]@{
  HasCorrectionsFile = Test-Path "C:\Users\HP\.copilot\memory\global\corrections.md"
  HasCorrectionKey = [bool](Select-String -Path "C:\Users\HP\.copilot\memory\global\preferences.json" -Pattern '"correctionLearning"')
  HasLearningRule = [bool](Select-String -Path "C:\Users\HP\.copilot\memory\global\profile.md" -Pattern "纠错")
}
$checks
```

Expected:

```text
HasCorrectionsFile : True
HasCorrectionKey   : True
HasLearningRule    : True
```

- [ ] **Step 5: 记录当前目录不执行提交**

Run:

```powershell
git -C "C:\Users\HP\.copilot" rev-parse --is-inside-work-tree
```

Expected: 非零退出或报错，记录“目标目录不是 Git 仓库，因此本轮不提交”。

### Task 3: 加入偏好学习技能并收紧项目记忆边界

**Files:**
- Create: `C:\Users\HP\.copilot\skills\preference-learning\SKILL.md`
- Modify: `C:\Users\HP\.copilot\skills\memory-handoff\SKILL.md`
- Modify: `C:\Users\HP\.copilot\copilot-instructions.md`

- [ ] **Step 1: 写一个会失败的技能检查**

Run:

```powershell
$checks = [pscustomobject]@{
  HasPreferenceLearningSkill = Test-Path "C:\Users\HP\.copilot\skills\preference-learning\SKILL.md"
  GlobalInstructionMentionsCorrection = Select-String -Path "C:\Users\HP\.copilot\copilot-instructions.md" -Pattern "用户明确纠正"
  MemoryHandoffKeepsDocsOut = Select-String -Path "C:\Users\HP\.copilot\skills\memory-handoff\SKILL.md" -Pattern "不写入项目正式文档"
}
$checks
```

Expected: 至少一项缺失。

- [ ] **Step 2: 创建偏好学习技能**

Create `C:\Users\HP\.copilot\skills\preference-learning\SKILL.md` with:

```md
---
name: preference-learning
description: 当用户明确表达稳定偏好或纠正既有做法时，将规则写入全局偏好层或纠错学习层。
---

使用该技能时：
1. 先判断这是稳定偏好还是一次性要求。
2. 稳定偏好写入 `C:\Users\HP\.copilot\memory\global\profile.md` 或 `preferences.json`。
3. 明确纠错写入 `C:\Users\HP\.copilot\memory\global\corrections.md`。
4. 不把项目正式文档写入运行时项目记忆目录。
```

- [ ] **Step 3: 更新全局指令和 memory-handoff 技能**

在 `C:\Users\HP\.copilot\copilot-instructions.md` 中追加：

```md
12. 当用户明确纠正表达、流程或长期偏好时，优先使用 `preference-learning` 相关规则，将稳定结论写入全局偏好层或纠错学习层。
```

将 `C:\Users\HP\.copilot\skills\memory-handoff\SKILL.md` 更新为：

```md
---
name: memory-handoff
description: 在任务结束或窗口切换前整理项目记忆目录下的 handoff.md、state.md 和 decisions.md，确保跨窗口连续性。
---

使用该技能时：
1. 先基于当前项目定位 `C:\Users\HP\.copilot\memory\projects\<project-id>\`。
2. 再在该目录下读取并更新 `handoff.md`、`state.md`。
3. 仅将长期稳定结论写入该目录下的 `decisions.md`。
4. 将 `handoff.md` 保持为单屏可读摘要。
5. 不将项目正式文档、长设计文档或实施计划写入项目记忆目录。
```

- [ ] **Step 4: 重新运行技能检查，确认通过**

Run:

```powershell
$checks = [pscustomobject]@{
  HasPreferenceLearningSkill = Test-Path "C:\Users\HP\.copilot\skills\preference-learning\SKILL.md"
  GlobalInstructionMentionsCorrection = [bool](Select-String -Path "C:\Users\HP\.copilot\copilot-instructions.md" -Pattern "用户明确纠正")
  MemoryHandoffKeepsDocsOut = [bool](Select-String -Path "C:\Users\HP\.copilot\skills\memory-handoff\SKILL.md" -Pattern "不将项目正式文档")
}
$checks
```

Expected:

```text
HasPreferenceLearningSkill      : True
GlobalInstructionMentionsCorrection : True
MemoryHandoffKeepsDocsOut       : True
```

- [ ] **Step 5: 记录当前目录不执行提交**

Run:

```powershell
git -C "C:\Users\HP\.copilot" rev-parse --is-inside-work-tree
```

Expected: 非零退出或报错，记录“目标目录不是 Git 仓库，因此本轮不提交”。

### Task 4: 把文档落盘规则同步到项目模板

**Files:**
- Modify: `C:\Users\HP\.copilot\templates\project-bootstrap\.github\copilot-instructions.md`
- Modify: `C:\Users\HP\.copilot\templates\project-bootstrap\.github\instructions\memory-hydration.instructions.md`
- Create: `C:\Users\HP\.copilot\templates\project-bootstrap\.github\instructions\document-placement.instructions.md`

- [ ] **Step 1: 写一个会失败的模板检查**

Run:

```powershell
$checks = [pscustomobject]@{
  HasDocPlacementInstruction = Test-Path "C:\Users\HP\.copilot\templates\project-bootstrap\.github\instructions\document-placement.instructions.md"
  RepoInstructionMentionsEDrive = Select-String -Path "C:\Users\HP\.copilot\templates\project-bootstrap\.github\copilot-instructions.md" -Pattern "E:\\copilotcli\\<项目名>"
  MemoryHydrationMentionsLightweightMemory = Select-String -Path "C:\Users\HP\.copilot\templates\project-bootstrap\.github\instructions\memory-hydration.instructions.md" -Pattern "不读取项目正式文档"
}
$checks
```

Expected: 至少一项缺失。

- [ ] **Step 2: 创建项目文档放置指令**

Create `C:\Users\HP\.copilot\templates\project-bootstrap\.github\instructions\document-placement.instructions.md` with:

```md
---
applyTo: "**"
---

当处理当前项目的正式文档时：
1. 需求、设计、计划、验证、复盘、交付说明默认写入 `E:\copilotcli\<项目名>`。
2. 不把项目正式长文档写入 `C:\Users\HP\.copilot\memory\projects\<project-id>`。
3. 项目记忆目录只保留 `handoff.md`、`state.md`、`decisions.md`、`overview.md` 等轻量记忆文件。
```

- [ ] **Step 3: 最小化修改模板现有指令**

在 `C:\Users\HP\.copilot\templates\project-bootstrap\.github\copilot-instructions.md` 中追加：

```md
5. 当前项目的正式文档默认写入 `E:\copilotcli\<项目名>`，不要把长文档写入项目记忆目录。
```

在 `C:\Users\HP\.copilot\templates\project-bootstrap\.github\instructions\memory-hydration.instructions.md` 中追加：

```md
6. 项目记忆目录只用于轻量上下文恢复，不读取项目正式文档。
```

- [ ] **Step 4: 重新运行模板检查，确认通过**

Run:

```powershell
$checks = [pscustomobject]@{
  HasDocPlacementInstruction = Test-Path "C:\Users\HP\.copilot\templates\project-bootstrap\.github\instructions\document-placement.instructions.md"
  RepoInstructionMentionsEDrive = [bool](Select-String -Path "C:\Users\HP\.copilot\templates\project-bootstrap\.github\copilot-instructions.md" -Pattern "E:\\copilotcli\\<项目名>")
  MemoryHydrationMentionsLightweightMemory = [bool](Select-String -Path "C:\Users\HP\.copilot\templates\project-bootstrap\.github\instructions\memory-hydration.instructions.md" -Pattern "不读取项目正式文档")
}
$checks
```

Expected:

```text
HasDocPlacementInstruction            : True
RepoInstructionMentionsEDrive         : True
MemoryHydrationMentionsLightweightMemory : True
```

- [ ] **Step 5: 记录当前目录不执行提交**

Run:

```powershell
git -C "C:\Users\HP\.copilot" rev-parse --is-inside-work-tree
```

Expected: 非零退出或报错，记录“目标目录不是 Git 仓库，因此本轮不提交”。

### Task 5: 复制模板并做端到端验证

**Files:**
- Modify: `C:\Users\HP\Desktop\copilot-ecc-bootstrap-test\.github\copilot-instructions.md`
- Modify: `C:\Users\HP\Desktop\copilot-ecc-bootstrap-test\.github\instructions\memory-hydration.instructions.md`
- Create: `C:\Users\HP\Desktop\copilot-ecc-bootstrap-test\.github\instructions\document-placement.instructions.md`

- [ ] **Step 1: 写一个会失败的测试目录检查**

Run:

```powershell
$checks = [pscustomobject]@{
  HasDocPlacementInstruction = Test-Path "C:\Users\HP\Desktop\copilot-ecc-bootstrap-test\.github\instructions\document-placement.instructions.md"
  RepoInstructionMentionsEDrive = Select-String -Path "C:\Users\HP\Desktop\copilot-ecc-bootstrap-test\.github\copilot-instructions.md" -Pattern "E:\\copilotcli\\<项目名>"
}
$checks
```

Expected: 至少一项缺失。

- [ ] **Step 2: 复制模板到测试目录**

Run:

```powershell
Copy-Item -Path "C:\Users\HP\.copilot\templates\project-bootstrap\.github\*" -Destination "C:\Users\HP\Desktop\copilot-ecc-bootstrap-test\.github" -Recurse -Force
```

Expected: 测试目录中的 `.github` 文件与模板保持一致。

- [ ] **Step 3: 重新运行测试目录检查，确认模板同步**

Run:

```powershell
$checks = [pscustomobject]@{
  HasDocPlacementInstruction = Test-Path "C:\Users\HP\Desktop\copilot-ecc-bootstrap-test\.github\instructions\document-placement.instructions.md"
  RepoInstructionMentionsEDrive = [bool](Select-String -Path "C:\Users\HP\Desktop\copilot-ecc-bootstrap-test\.github\copilot-instructions.md" -Pattern "E:\\copilotcli\\<项目名>")
}
$checks
```

Expected:

```text
HasDocPlacementInstruction : True
RepoInstructionMentionsEDrive : True
```

- [ ] **Step 4: 用 Copilot CLI 做交互验证**

Run:

```powershell
Set-Location "C:\Users\HP\Desktop\copilot-ecc-bootstrap-test"
copilot
```

在交互会话中依次执行：

```text
/cwd
/skills list
/mcp show
/instructions
/env
```

Expected:

- `/cwd` 返回测试目录
- `/skills list` 能看到 `preference-learning`
- `/mcp show` 正常显示服务器
- `/instructions` 能看到新增的项目文档放置指令
- `/env` 能正常展示已加载环境

- [ ] **Step 5: 记录当前目录不执行提交**

Run:

```powershell
git -C "C:\Users\HP\Desktop\copilot-ecc-bootstrap-test" rev-parse --is-inside-work-tree
```

Expected: 非零退出或报错，记录“测试目录不是 Git 仓库，因此本轮不提交”。
