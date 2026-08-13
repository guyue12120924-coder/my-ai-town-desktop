# 居民 Prompt 配置

AI Town 的居民 Prompt 现在按以下顺序组成，并在真正发送给模型 Provider 前统一注入：

1. **全局模型 Prompt**：`res://prompts/base.system.prompt`
2. **AI Town 运行规则**：现有 `AgentPromptCompiler` 生成的系统合同、世界规则和稳定资料
3. **角色专属 Prompt**：当前居民的角色档案与 `custom_prompt`
4. **本轮动态上下文**：事件、记忆、附近人物、地点、可执行动作等，继续放在 user message 中

后面的角色层只能影响该居民的人格、表达和行为偏好，不能覆盖世界事实、合法动作范围或 AI Town 的系统合同。

## 修改全局模型 Prompt

直接编辑：

```text
game/prompts/base.system.prompt
```

这里适合放所有居民共同遵守的模型级规则。例如总体扮演方式、连续性要求、通用表达习惯等。

## 为单个居民设置专属 Prompt

仓库内置默认档案文件：

```text
game/residents/resident_profiles.json
```

格式：

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
      "long_term_memory": "可选的长期记忆摘要"
    }
  }
}
```

所有字段都是可选的。已有角色创建/编辑页面中的姓名、性格、核心欲望、说话方式、职业、工作地和住处仍然会自动进入角色 Prompt；`resident_profiles.json` 或运行时保存的同名字段用于补充或覆盖这些内容。

## 桌面运行时保存

`ResidentPersonaProfile.gd` 会优先读取玩家运行时保存的：

```text
user://resident_profiles.json
```

因此正式打包后不需要修改程序安装目录。运行时用户档案优先级高于仓库内置默认档案。

## 代码入口

- `game/agent/ResidentPersonaProfile.gd`：读取、保存和组装居民角色档案
- `game/agent/ResidentPromptInjector.gd`：组装全局 Prompt、AI Town 运行 Prompt 和角色 Prompt
- `game/agent/DecisionExecution.gd`：在真正调用 Provider 前执行最终注入
- `game/tests/agent/prompt/resident_persona_prompt_test.gd`：验证三层 Prompt 最终确实进入 Provider 请求
