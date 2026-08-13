extends SceneTree


const DecisionExecutionScript := preload("res://agent/DecisionExecution.gd")
const PromptBudgetScript := preload("res://agent/PromptBudgetManager.gd")


class CapturingCompiler:
	extends RefCounted

	var memory_prompt := ""
	var retry_feedback := ""

	func compile(
		_wake_packet: Dictionary,
		memory: String,
		retry: String = "",
	) -> Dictionary:
		memory_prompt = memory
		retry_feedback = retry
		return {
			"messages": [
				{"role": "system", "content": "SYSTEM"},
				{"role": "user", "content": "CONTEXT"},
			],
		}


class NoopProvider:
	extends RefCounted

	func request_decision(_request: Dictionary, _on_complete: Callable) -> void:
		pass


var _failed := 0


func _initialize() -> void:
	var long_memory := _repeated_text("M", PromptBudgetScript.MEMORY_PROMPT_MAX_CHARS + 2000)
	var long_retry := _repeated_text("R", PromptBudgetScript.RETRY_FEEDBACK_MAX_CHARS + 1000)
	var compiler := CapturingCompiler.new()
	var execution: RefCounted = DecisionExecutionScript.new(NoopProvider.new(), compiler)
	execution.call(
		"request_decision",
		{"me": {"resident_id": "prompt-budget-test", "attributes": {"name": "预算测试"}}},
		{"decision_id": "prompt-budget-1"},
		long_memory,
		{},
		Callable(),
		long_retry,
	)

	_expect(
		compiler.memory_prompt.length() <= PromptBudgetScript.MEMORY_PROMPT_MAX_CHARS,
		"记忆 Prompt 在进入编译器前受预算限制",
	)
	_expect(
		compiler.memory_prompt.contains("较早的记忆内容因上下文预算被省略"),
		"记忆截断会留下明确标记",
	)
	_expect(
		compiler.retry_feedback.length() <= PromptBudgetScript.RETRY_FEEDBACK_MAX_CHARS,
		"重试反馈严格保持在预算内",
	)
	_expect(
		compiler.retry_feedback.contains("重试反馈因上下文预算已截断"),
		"重试反馈截断会留下明确标记",
	)

	var chinese_prompt := "保持角色核心性格稳定，并根据当前事实做出决定。"
	var english_prompt := "Keep the resident consistent with current world facts."
	_expect(
		PromptBudgetScript.estimate_tokens(chinese_prompt) >= chinese_prompt.length() - 2,
		"中文 Prompt 的 Token 粗估不会按英文密度明显低估",
	)
	_expect(
		PromptBudgetScript.estimate_tokens(english_prompt) < english_prompt.length(),
		"英文 Prompt 仍使用较低密度的保守粗估",
	)
	_expect(
		PromptBudgetScript.estimate_tokens("角色 AI 123") > 0,
		"中英混合 Prompt 可以得到稳定 Token 粗估",
	)

	if _failed == 0:
		print("PROMPT_BUDGET_PASS")
		quit(0)
	else:
		printerr("PROMPT_BUDGET_FAIL count=%d" % _failed)
		quit(1)


func _repeated_text(piece: String, count: int) -> String:
	var result := ""
	for _index: int in count:
		result += piece
	return result


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failed += 1
	printerr("[FAIL] %s" % label)
