extends SceneTree


const DecisionExecutionScript := preload("res://agent/DecisionExecution.gd")
const PersonaProfileScript := preload("res://agent/ResidentPersonaProfile.gd")
const PromptInjectorScript := preload("res://agent/ResidentPromptInjector.gd")


class FakeCompiler:
	extends RefCounted

	func compile(
		_wake_packet: Dictionary,
		_memory_prompt: String,
		_retry_feedback: String = "",
	) -> Dictionary:
		return {
			"request_kind": "resident_decision",
			"messages": [
				{"role": "system", "content": "BASE_SYSTEM_PROMPT"},
				{"role": "user", "content": "CURRENT_CONTEXT"},
			],
		}


class FakeProvider:
	extends RefCounted

	var captured_request: Dictionary = {}

	func request_decision(request: Dictionary, _on_complete: Callable) -> void:
		captured_request = request.duplicate(true)


func _initialize() -> void:
	var initialization := {
		"me": {
			"resident_id": "resident-persona-test",
			"attributes": {
				"name": "林岚",
				"desire": "守住花房并保护熟悉的人",
				"personality": "冷静、警惕陌生人，但会保护答应过的人",
				"speech": "说话简短，先确认事实",
			},
			"social_state": {
				"home": "林岚的住家",
				"job": "花房店员",
				"workplace": "花房咖啡馆",
			},
		},
	}

	var store: RefCounted = PersonaProfileScript.new()
	var persona_text := String(store.call(
		"build_prompt",
		"resident-persona-test",
		initialization,
	))
	_expect(persona_text.contains("<resident_persona>"), "角色卡生成独立 persona 区块")
	_expect(persona_text.contains("冷静、警惕陌生人"), "角色卡读取真实 personality")
	_expect(persona_text.contains("说话简短，先确认事实"), "角色卡读取真实 speech")
	_expect(persona_text.contains("花房店员"), "职业背景进入 persona")
	_expect(persona_text.contains("守住花房并保护熟悉的人"), "欲望进入长期目标")

	var injector: RefCounted = PromptInjectorScript.new()
	var injected := String(injector.call(
		"inject",
		"BASE_SYSTEM_PROMPT",
		initialization,
	))
	_expect(injected.begins_with("BASE_SYSTEM_PROMPT"), "保留原有 system prompt")
	_expect(injected.contains("<resident_persona>"), "persona 注入 system prompt")

	var provider := FakeProvider.new()
	var execution: RefCounted = DecisionExecutionScript.new(
		provider,
		FakeCompiler.new(),
	)
	execution.call(
		"request_decision",
		initialization,
		{"decision_id": "persona-chain-1"},
		"",
		{},
		Callable(),
		"",
	)
	var messages := provider.captured_request.get("messages", []) as Array
	_expect(messages.size() == 2, "模型请求保留 system/user 两层消息")
	if messages.size() == 2:
		var system_text := String((messages[0] as Dictionary).get("content", ""))
		var user_text := String((messages[1] as Dictionary).get("content", ""))
		_expect(system_text.contains("<resident_persona>"), "实际 provider 请求包含 persona")
		_expect(system_text.contains("冷静、警惕陌生人"), "provider 收到对应居民人格")
		_expect(user_text == "CURRENT_CONTEXT", "persona 注入不污染动态用户上下文")

	if _failed == 0:
		print("RESIDENT_PERSONA_PROMPT_PASS")
		quit(0)
	else:
		printerr("RESIDENT_PERSONA_PROMPT_FAIL count=%d" % _failed)
		quit(1)


var _failed := 0


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failed += 1
	printerr("[FAIL] %s" % label)
