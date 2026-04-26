# Copilot CLI 记忆生命周期与审批边界 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 Copilot CLI 落地长期/短期记忆分层、短期记忆压缩与自动清理、以及高低风险审批边界规则，并同步到全局规则、技能和模板中。

**Architecture:** 采用轻量规则型方案，不引入复杂评分引擎。先新增全局记忆生命周期文档作为单一规则源，再把规则同步到全局偏好层、纠错层、技能和模板，最后在测试目录验证“轻量记忆恢复 + 低风险自动执行 + 高风险需批准”三项行为。

**Tech Stack:** Markdown 指令与设计文档、JSON 偏好配置、PowerShell 校验命令、Copilot CLI 交互验证

---

## File Structure

- Create: `C:\Users\HP\.copilot\memory-lifecycle.md` — 记忆分层、压缩、清理、升级规则的单一说明文档
- Modify: `C:\Users\HP\.copilot\copilot-instructions.md` — 固化审批边界与记忆生命周期的全局规则
- Modify: `C:\Users\HP\.copilot\memory\global\profile.md` — 补充跨天续做、短期压缩与审批边界偏好
- Modify: `C:\Users\HP\.copilot\memory\global\preferences.json` — 增加生命周期与审批相关键
- Modify: `C:\Users\HP\.copilot\memory\global\corrections.md` — 记录最新纠错：短期记忆压缩/清理与审批边界
- Modify: `C:\Users\HP\.copilot\skills\memory-handoff\SKILL.md` — 在窗口切换与任务结束前执行压缩与清理判断
- Modify: `C:\Users\HP\.copilot\skills\preference-learning\SKILL.md` — 明确长期/短期分流条件
- Create: `C:\Users\HP\.copilot\templates\project-bootstrap\.github\instructions\approval-boundary.instructions.md` — 项目模板中的审批边界规则
- Modify: `C:\Users\HP\.copilot\templates\project-bootstrap\.github\instructions\memory-hydration.instructions.md` — 明确只读取轻量记忆并在收尾时触发压缩
- Modify: `C:\Users\HP\.copilot\templates\project-bootstrap\.github\copilot-instructions.md` — 同步项目级审批与记忆收尾规则
- Create: `C:\Users\HP\Desktop\copilot-ecc-bootstrap-test\.github\instructions\approval-boundary.instructions.md` — 用于模板同步验证
- Modify: `C:\Users\HP\Desktop\copilot-ecc-bootstrap-test\.github\instructions\memory-hydration.instructions.md` — 用于模板同步验证
- Modify: `C:\Users\HP\Desktop\copilot-ecc-bootstrap-test\.github\copilot-instructions.md` — 用于模板同步验证

### Task 1: 新增全局记忆生命周期规则源

**Files:**
- Create: `C:\Users\HP\.copilot\memory-lifecycle.md`
- Test: `C:\Users\HP\.copilot\memory-lifecycle.md`

- [ ] **Step 1: 运行基线检查，确认规则文件尚未完整存在**

Run:

```powershell
$checks = [pscustomobject]@{
  HasMemoryLifecycleDoc = Test-Path "C:\Users\HP\.copilot\memory-lifecycle.md"
  ExistingLifecycleRule = [bool](Select-String -Path "C:\Users\HP\.copilot\copilot-instructions.md" -Pattern "短期记忆")
}
$checks
```

Expected:

```text
HasMemoryLifecycleDoc : False
ExistingLifecycleRule : False
```

- [ ] **Step 2: 创建记忆生命周期说明文档**

Write:

```md
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

压缩后只保留：

- 当前目标
- 当前阶段
- 已完成项
- 下一步
- 阻塞点
- 必要引用路径

## 4. 清理

- 压缩后自动清理无复用价值内容
- 冗长过程描述、重复信息、临时调试记录默认删除

## 5. 升级判断

- 稳定偏好 → `memory\global\profile.md` 或 `preferences.json`
- 明确纠错 → `memory\global\corrections.md`
- 项目长期知识 → `memory\projects\<project-id>\decisions.md` 或 `overview.md`
```

- [ ] **Step 3: 验证文件创建成功**

Run:

```powershell
Get-Content "C:\Users\HP\.copilot\memory-lifecycle.md" | Select-Object -First 20
```

Expected: 输出标题 `# Copilot CLI 记忆生命周期规则` 和“分层 / 分流 / 压缩 / 清理 / 升级判断”章节。

- [ ] **Step 4: 记录当前目录不执行提交**

Run:

```powershell
git -C "C:\Users\HP\.copilot" rev-parse --is-inside-work-tree
```

Expected: 非零退出或报错，记录“目标目录不是 Git 仓库，因此本轮不提交”。

### Task 2: 固化全局审批边界与生命周期规则

**Files:**
- Modify: `C:\Users\HP\.copilot\copilot-instructions.md`
- Test: `C:\Users\HP\.copilot\copilot-instructions.md`

- [ ] **Step 1: 检查全局工作内核中尚未完整声明的新规则**

Run:

```powershell
$checks = [pscustomobject]@{
  HasLifecycleRule = [bool](Select-String -Path "C:\Users\HP\.copilot\copilot-instructions.md" -Pattern "短期记忆要进行上下文压缩")
  HasApprovalRule = [bool](Select-String -Path "C:\Users\HP\.copilot\copilot-instructions.md" -Pattern "系统安全")
}
$checks
```

Expected: 至少一项为 `False`。

- [ ] **Step 2: 在全局工作内核中追加审批与生命周期规则**

Append:

```md
13. 每天新增记忆默认先进入短期任务层；只有稳定偏好、明确纠错或可复用项目长期知识，才升级写入长期层。
14. 短期任务记忆在任务完成前、窗口切换前或用户要求跨天续做时，必须先压缩成单屏摘要，再自动清理无保留价值内容。
15. 读取记忆文件、常规检查、普通搜索、低风险命令和短期记忆压缩/清理默认自动执行，不逐条请求确认。
16. 涉及系统安全、全局配置重大变更、重构、删除文件、操作本机重要设置、个人隐私或重要数据上传删除时，必须先得到用户批准后执行。
17. 若无法明确判断风险等级，按高风险处理。
```

- [ ] **Step 3: 验证全局工作内核命中新规则**

Run:

```powershell
$checks = [pscustomobject]@{
  HasLifecycleRule = [bool](Select-String -Path "C:\Users\HP\.copilot\copilot-instructions.md" -Pattern "短期任务记忆在任务完成前")
  HasApprovalRule = [bool](Select-String -Path "C:\Users\HP\.copilot\copilot-instructions.md" -Pattern "涉及系统安全")
  HasGrayRule = [bool](Select-String -Path "C:\Users\HP\.copilot\copilot-instructions.md" -Pattern "按高风险处理")
}
$checks
```

Expected:

```text
HasLifecycleRule : True
HasApprovalRule  : True
HasGrayRule      : True
```

- [ ] **Step 4: 记录当前目录不执行提交**

Run:

```powershell
git -C "C:\Users\HP\.copilot" rev-parse --is-inside-work-tree
```

Expected: 非零退出或报错，记录“目标目录不是 Git 仓库，因此本轮不提交”。

### Task 3: 补齐全局偏好层与纠错层

**Files:**
- Modify: `C:\Users\HP\.copilot\memory\global\profile.md`
- Modify: `C:\Users\HP\.copilot\memory\global\preferences.json`
- Modify: `C:\Users\HP\.copilot\memory\global\corrections.md`
- Test: `C:\Users\HP\.copilot\memory\global\profile.md`
- Test: `C:\Users\HP\.copilot\memory\global\preferences.json`
- Test: `C:\Users\HP\.copilot\memory\global\corrections.md`

- [ ] **Step 1: 检查偏好层与纠错层缺失项**

Run:

```powershell
$checks = [pscustomobject]@{
  ProfileHasCompressionRule = [bool](Select-String -Path "C:\Users\HP\.copilot\memory\global\profile.md" -Pattern "短期任务记忆")
  JsonHasLifecycleKey = [bool](Select-String -Path "C:\Users\HP\.copilot\memory\global\preferences.json" -Pattern '"memoryLifecycle"')
  JsonHasApprovalMode = [bool](Select-String -Path "C:\Users\HP\.copilot\memory\global\preferences.json" -Pattern '"approvalPolicy"')
  CorrectionsHasLifecycle = [bool](Select-String -Path "C:\Users\HP\.copilot\memory\global\corrections.md" -Pattern "短期记忆")
}
$checks
```

Expected: 至少两项为 `False`。

- [ ] **Step 2: 在 profile.md 中补充稳定偏好**

Append:

```md
- 每天新增记忆应先区分长期与短期；短期任务记忆优先压缩后再决定是否保留
- 短期任务记忆在任务完成或窗口切换前自动压缩与清理，以降低存储与恢复成本
- 审批边界遵循“高风险先批准，低风险默认自动执行”
```

- [ ] **Step 3: 在 preferences.json 中补充结构化键**

Merge:

```json
{
  "memoryLifecycle": "long-term-vs-short-term-with-compress-and-cleanup",
  "shortTermMemoryCleanup": "auto-after-compression",
  "approvalPolicy": "auto-low-risk-confirm-high-risk",
  "riskFallback": "treat-unknown-as-high-risk"
}
```

- [ ] **Step 4: 在 corrections.md 中补充本轮纠错**

Append:

```md
- 触发场景：用户要求每天新增记忆区分长期与短期，并强调短期任务记忆需要压缩与定期清理时
  - 正确做法：先将新增记忆默认落入短期层，任务收尾前压缩，再判断是否升级到长期层
  - 避免事项：不要把过程性上下文直接累积到长期记忆或长期保留在短期层中
- 触发场景：执行读取记忆文件、普通命令、常规检查等低风险动作时
  - 正确做法：默认自动执行
  - 避免事项：不要把低风险动作也当作需审批操作
- 触发场景：涉及系统安全、全局配置重大变更、重构、删除文件、本机重要设置、个人隐私或重要数据上传删除时
  - 正确做法：先说明影响并请求用户批准
  - 避免事项：不要在高风险或灰区动作上跳过审批
```

- [ ] **Step 5: 重新运行检查，确认三类文件都命中新规则**

Run:

```powershell
$checks = [pscustomobject]@{
  ProfileHasCompressionRule = [bool](Select-String -Path "C:\Users\HP\.copilot\memory\global\profile.md" -Pattern "短期任务记忆")
  JsonHasLifecycleKey = [bool](Select-String -Path "C:\Users\HP\.copilot\memory\global\preferences.json" -Pattern '"memoryLifecycle"')
  JsonHasApprovalMode = [bool](Select-String -Path "C:\Users\HP\.copilot\memory\global\preferences.json" -Pattern '"approvalPolicy"')
  CorrectionsHasLifecycle = [bool](Select-String -Path "C:\Users\HP\.copilot\memory\global\corrections.md" -Pattern "先将新增记忆默认落入短期层")
}
$checks
```

Expected:

```text
ProfileHasCompressionRule : True
JsonHasLifecycleKey       : True
JsonHasApprovalMode       : True
CorrectionsHasLifecycle   : True
```

- [ ] **Step 6: 记录当前目录不执行提交**

Run:

```powershell
git -C "C:\Users\HP\.copilot" rev-parse --is-inside-work-tree
```

Expected: 非零退出或报错，记录“目标目录不是 Git 仓库，因此本轮不提交”。

### Task 4: 更新技能层

**Files:**
- Modify: `C:\Users\HP\.copilot\skills\memory-handoff\SKILL.md`
- Modify: `C:\Users\HP\.copilot\skills\preference-learning\SKILL.md`
- Test: `C:\Users\HP\.copilot\skills\memory-handoff\SKILL.md`
- Test: `C:\Users\HP\.copilot\skills\preference-learning\SKILL.md`

- [ ] **Step 1: 检查两个技能文件缺失的规则**

Run:

```powershell
$checks = [pscustomobject]@{
  MemoryHandoffHasCompression = [bool](Select-String -Path "C:\Users\HP\.copilot\skills\memory-handoff\SKILL.md" -Pattern "压缩")
  MemoryHandoffHasCleanup = [bool](Select-String -Path "C:\Users\HP\.copilot\skills\memory-handoff\SKILL.md" -Pattern "清理")
  PreferenceLearningHasSplit = [bool](Select-String -Path "C:\Users\HP\.copilot\skills\preference-learning\SKILL.md" -Pattern "长期")
}
$checks
```

Expected: 至少一项为 `False`。

- [ ] **Step 2: 扩展 memory-handoff 技能**

Update content to include:

```md
6. 在任务结束、窗口切换或用户要求跨天续做前，先把短期任务状态压缩为单屏摘要。
7. 压缩后判断是否存在长期保留价值：稳定偏好写入全局偏好层，明确纠错写入全局纠错层，项目长期知识写入 decisions.md 或 overview.md。
8. 对无长期价值的过程性短期内容进行清理，只保留当前状态、下一步、阻塞点与必要引用路径。
```

- [ ] **Step 3: 扩展 preference-learning 技能**

Update content to include:

```md
5. 每天新增记忆默认先视为短期任务记忆，不直接写入长期层。
6. 只有稳定偏好、明确纠错或可跨会话复用的项目长期知识，才允许升级写入长期层。
```

- [ ] **Step 4: 重新运行技能检查**

Run:

```powershell
$checks = [pscustomobject]@{
  MemoryHandoffHasCompression = [bool](Select-String -Path "C:\Users\HP\.copilot\skills\memory-handoff\SKILL.md" -Pattern "压缩为单屏摘要")
  MemoryHandoffHasCleanup = [bool](Select-String -Path "C:\Users\HP\.copilot\skills\memory-handoff\SKILL.md" -Pattern "进行清理")
  PreferenceLearningHasSplit = [bool](Select-String -Path "C:\Users\HP\.copilot\skills\preference-learning\SKILL.md" -Pattern "默认先视为短期任务记忆")
}
$checks
```

Expected:

```text
MemoryHandoffHasCompression : True
MemoryHandoffHasCleanup     : True
PreferenceLearningHasSplit  : True
```

- [ ] **Step 5: 记录当前目录不执行提交**

Run:

```powershell
git -C "C:\Users\HP\.copilot" rev-parse --is-inside-work-tree
```

Expected: 非零退出或报错，记录“目标目录不是 Git 仓库，因此本轮不提交”。

### Task 5: 更新项目模板规则

**Files:**
- Create: `C:\Users\HP\.copilot\templates\project-bootstrap\.github\instructions\approval-boundary.instructions.md`
- Modify: `C:\Users\HP\.copilot\templates\project-bootstrap\.github\instructions\memory-hydration.instructions.md`
- Modify: `C:\Users\HP\.copilot\templates\project-bootstrap\.github\copilot-instructions.md`
- Test: `C:\Users\HP\.copilot\templates\project-bootstrap\.github\instructions\approval-boundary.instructions.md`
- Test: `C:\Users\HP\.copilot\templates\project-bootstrap\.github\instructions\memory-hydration.instructions.md`
- Test: `C:\Users\HP\.copilot\templates\project-bootstrap\.github\copilot-instructions.md`

- [ ] **Step 1: 运行模板基线检查**

Run:

```powershell
$checks = [pscustomobject]@{
  HasApprovalBoundary = Test-Path "C:\Users\HP\.copilot\templates\project-bootstrap\.github\instructions\approval-boundary.instructions.md"
  HydrationHasCompression = [bool](Select-String -Path "C:\Users\HP\.copilot\templates\project-bootstrap\.github\instructions\memory-hydration.instructions.md" -Pattern "压缩")
  RepoInstructionHasApproval = [bool](Select-String -Path "C:\Users\HP\.copilot\templates\project-bootstrap\.github\copilot-instructions.md" -Pattern "高风险")
}
$checks
```

Expected: 至少两项为 `False`。

- [ ] **Step 2: 创建审批边界模板指令**

Create:

```md
---
applyTo: "**"
---

当处理当前项目时：
1. 读取记忆文件、普通搜索、常规检查、低风险命令默认自动执行。
2. 涉及系统安全、重构、删除文件、本机重要设置、全局配置重大变更、个人隐私或重要数据上传删除时，必须先请求用户批准。
3. 若无法判断风险等级，按高风险处理。
```

- [ ] **Step 3: 扩展 memory-hydration 模板指令**

Append:

```md
7. 任务收尾或跨天续做前，应先把短期任务记忆压缩成单屏摘要，再清理无保留价值内容。
8. 只有稳定偏好、明确纠错或项目长期知识，才升级到长期层；其余保持为轻量短期摘要。
```

- [ ] **Step 4: 扩展仓库级模板指令**

Append:

```md
6. 低风险命令默认自动执行，不逐条确认；高风险或灰区动作必须先获批。
7. 项目记忆目录中的短期任务记忆应在收尾时压缩和清理，不长期堆积过程性内容。
```

- [ ] **Step 5: 重新运行模板检查**

Run:

```powershell
$checks = [pscustomobject]@{
  HasApprovalBoundary = Test-Path "C:\Users\HP\.copilot\templates\project-bootstrap\.github\instructions\approval-boundary.instructions.md"
  HydrationHasCompression = [bool](Select-String -Path "C:\Users\HP\.copilot\templates\project-bootstrap\.github\instructions\memory-hydration.instructions.md" -Pattern "压缩成单屏摘要")
  RepoInstructionHasApproval = [bool](Select-String -Path "C:\Users\HP\.copilot\templates\project-bootstrap\.github\copilot-instructions.md" -Pattern "低风险命令默认自动执行")
}
$checks
```

Expected:

```text
HasApprovalBoundary    : True
HydrationHasCompression: True
RepoInstructionHasApproval : True
```

- [ ] **Step 6: 记录当前目录不执行提交**

Run:

```powershell
git -C "C:\Users\HP\.copilot" rev-parse --is-inside-work-tree
```

Expected: 非零退出或报错，记录“目标目录不是 Git 仓库，因此本轮不提交”。

### Task 6: 同步模板到测试目录并验证

**Files:**
- Create: `C:\Users\HP\Desktop\copilot-ecc-bootstrap-test\.github\instructions\approval-boundary.instructions.md`
- Modify: `C:\Users\HP\Desktop\copilot-ecc-bootstrap-test\.github\instructions\memory-hydration.instructions.md`
- Modify: `C:\Users\HP\Desktop\copilot-ecc-bootstrap-test\.github\copilot-instructions.md`
- Test: `C:\Users\HP\Desktop\copilot-ecc-bootstrap-test\.github\instructions\approval-boundary.instructions.md`
- Test: `C:\Users\HP\Desktop\copilot-ecc-bootstrap-test\.github\instructions\memory-hydration.instructions.md`
- Test: `C:\Users\HP\Desktop\copilot-ecc-bootstrap-test\.github\copilot-instructions.md`

- [ ] **Step 1: 复制模板到测试目录**

Run:

```powershell
Copy-Item -Path "C:\Users\HP\.copilot\templates\project-bootstrap\.github\*" -Destination "C:\Users\HP\Desktop\copilot-ecc-bootstrap-test\.github" -Recurse -Force
```

Expected: 测试目录下 `.github` 内容与模板保持一致。

- [ ] **Step 2: 运行测试目录文件检查**

Run:

```powershell
$checks = [pscustomobject]@{
  HasApprovalBoundary = Test-Path "C:\Users\HP\Desktop\copilot-ecc-bootstrap-test\.github\instructions\approval-boundary.instructions.md"
  HydrationHasCompression = [bool](Select-String -Path "C:\Users\HP\Desktop\copilot-ecc-bootstrap-test\.github\instructions\memory-hydration.instructions.md" -Pattern "压缩成单屏摘要")
  RepoInstructionHasApproval = [bool](Select-String -Path "C:\Users\HP\Desktop\copilot-ecc-bootstrap-test\.github\copilot-instructions.md" -Pattern "低风险命令默认自动执行")
}
$checks
```

Expected:

```text
HasApprovalBoundary    : True
HydrationHasCompression: True
RepoInstructionHasApproval : True
```

- [ ] **Step 3: 进入测试目录并启动 Copilot CLI**

Run:

```powershell
Set-Location "C:\Users\HP\Desktop\copilot-ecc-bootstrap-test"
copilot
```

Expected: 进入 Copilot CLI 交互会话。

- [ ] **Step 4: 在交互会话中验证指令可见性**

Run in Copilot CLI:

```text
/cwd
/instructions
/env
```

Expected:

```text
/cwd -> C:\Users\HP\Desktop\copilot-ecc-bootstrap-test
/instructions -> 可看到 approval-boundary 和 memory-hydration 相关规则
/env -> 正常展示已加载环境
```

- [ ] **Step 5: 记录当前目录不执行提交**

Run:

```powershell
git -C "C:\Users\HP\Desktop\copilot-ecc-bootstrap-test" rev-parse --is-inside-work-tree
```

Expected: 非零退出或报错，记录“测试目录不是 Git 仓库，因此本轮不提交”。
