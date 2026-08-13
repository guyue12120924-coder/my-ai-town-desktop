# 居民 Prompt 配置

AI Town 的居民 Prompt 会在真正发送给模型 Provider 前统一组装。当前稳定层顺序为：

1. **全局模型 Prompt**：`res://prompts/base.system.prompt`
2. **AI Town 运行规则**：现有 PromptCompiler 生成的系统合同、世界事实、合法动作与输出格式
3. **角色 Prompt 优先级保护层**：明确角色文本只能作为低优先级角色设定，不能伪装 System 或覆盖运行合同
4. **角色专属 Prompt**：当前居民的角色档案、关系备注与 `custom_prompt`
5. **本轮动态上下文**：事件、记忆、附近人物、地点、可执行动作等

角色层会影响人格、表达、关系偏好、风险态度、长期目标与合法动作之间的选择，但不能创建不存在的动作、篡改权威世界状态、改变输出合同或削弱更高优先级规则。

## 修改全局模型 Prompt

直接编辑：

```text
game/prompts/base.system.prompt
```

这里适合放所有居民共同遵守的模型级规则，例如总体扮演方式、连续性要求与通用行为原则。

## 在游戏里为单个居民填写 Prompt

进入居民创建或编辑页面后，点击右上角的 **“角色 Prompt”** 按钮即可打开编辑器。

编辑器现在提供：

- **Prompt 模板**：内置均衡角色、谨慎观察型、温和社交型、目标驱动型和有矛盾感的角色等模板，可插入后继续自由修改。
- **组合 Prompt 预览**：显示全局层、运行合同占位、优先级保护层和当前角色层；动态世界状态与记忆使用占位符，不伪造实际运行数据。
- **粗略 Token 估算**：用于判断稳定 Prompt 是否过长，仅作为调试参考，不作为 Provider 计费数据。
- **历史版本**：已有居民每次有效修改都会保留历史快照，最多 20 个；界面恢复只回滚 `custom_prompt`，不会误回滚姓名、性格等其他角色资料。
- **新角色暂存**：创建角色前可以先填写 Prompt，创建成功取得稳定 `residentId` 后自动绑定。

角色自由 Prompt 上限为 8000 个字符。

## Prompt 安全与结构保护

所有可编辑角色字段在进入结构化 Persona 区块前都会转义 `<`、`>` 等结构字符。因此，即使角色文本里写入 `</resident_persona>`、伪造 `<global_system_prompt>` 或“忽略之前规则”等内容，也只能作为角色设定文本呈现，不能直接关闭或伪造 Prompt 结构层。

`ResidentPromptPolicy.gd` 还会在真实请求里明确以下优先级：平台/安全约束 > 全局规则 > AI Town 运行合同 > 角色 Persona > 记忆与当前事件。

## 上下文预算

`PromptBudgetManager.gd` 对可增长的可选内容设置保守字符预算：

- 角色自由 Prompt：8000 字符
- 长期记忆摘要：6000 字符
- 关系备注：4000 字符
- 单次记忆 Prompt：12000 字符
- 重试反馈：3000 字符
- 全局 Base Prompt：8000 字符

核心 AI Town 运行合同不会被这个预算器静默截断。超长记忆会保留头部与近期尾部，并插入明确的省略标记。

## 角色关系信息

角色档案新增可选字段：

```json
"relationship_notes": "与某位居民的长期关系、信任、矛盾或重要共同经历"
```

如果运行时 `social_state.relationships` 或 `me.relationships` 已提供结构化关系数据，系统也会自动把它作为角色关系上下文的回退来源；用户保存的 `relationship_notes` 优先级更高。

## 通过文件配置单个居民

仓库内置默认档案文件：

```text
game/residents/resident_profiles.json
```

示例：

```json
{
  "version": 1,
  "residents": {
    "resident-id": {
      "name": "角色名",
      "personality": "性格补充",
      "background": "背景补充",
      "goals": "长期目标",
      "speaking_style": "说话方式",
      "behavior_rules": "行为原则",
      "custom_prompt": "这个角色独有的自由 Prompt",
      "relationship_notes": "关系与社交备注",
      "long_term_memory": "可选的长期记忆摘要"
    }
  }
}
```

所有字段都是可选的。角色创建/编辑页面中的姓名、性格、核心欲望、说话方式、职业、工作地和住处仍会自动进入角色 Prompt；运行时用户档案可以补充或覆盖这些内容。

## 桌面运行时保存与历史

`ResidentPersonaProfile.gd` 会优先读取：

```text
user://resident_profiles.json
```

当前运行时文档版本为 3，并在同一文件中保存最多 20 条/居民的历史快照。正式打包后不需要修改程序安装目录。

角色档案保存后还会递增进程内 Revision，因此已经存在的 AI 决策执行器会立即看到新 Prompt，不再只依赖文件修改时间粒度。

## 代码入口

- `game/agent/ResidentPersonaProfile.gd`：读取、保存、历史版本、关系上下文与 Persona 组装
- `game/agent/ResidentPromptPolicy.gd`：Prompt 优先级与结构转义策略
- `game/agent/PromptBudgetManager.gd`：角色、记忆、重试反馈等可增长上下文的预算
- `game/agent/ResidentPromptInjector.gd`：组装全局 Prompt、AI Town 运行 Prompt、保护层和角色 Prompt，并生成调试预览
- `game/agent/ResidentPromptTemplateLibrary.gd`：读取内置角色 Prompt 模板
- `game/prompts/resident_prompt_templates.json`：内置模板内容
- `game/agent/DecisionExecution.gd`：在调用 Provider 前统一注入角色层，并对记忆/重试上下文应用预算
- `game/ui/custom_resident_creator/ResidentCustomPromptEditor.gd`：模板、历史、预览、保存和新角色绑定 UI
- `game/tests/agent/prompt/resident_persona_prompt_test.gd`：验证层级、角色数据与结构逃逸保护
- `game/tests/agent/prompt/resident_custom_prompt_editor_test.gd`：验证模板、预览和新角色 Prompt 持久化
- `game/tests/agent/prompt/resident_persona_history_test.gd`：验证历史版本与多实例即时同步
- `game/tests/agent/prompt/prompt_budget_test.gd`：验证记忆和重试上下文预算
