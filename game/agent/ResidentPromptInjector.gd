class_name ResidentPromptInjector
extends RefCounted

const PersonaProfileScript := preload("res://agent/ResidentPersonaProfile.gd")
const PromptBudgetScript := preload("res://agent/PromptBudgetManager.gd")
const PromptPolicyScript := preload("res://agent/ResidentPromptPolicy.gd")
const BASE_SYSTEM_PROMPT_PATH := "res://prompts/base.system.prompt"

var _persona: PersonaProfileScript
var _base_system_prompt := ""


func _init() -> void:
	_persona = PersonaProfileScript.new()
	_base_system_prompt = _load_base_system_prompt()


func build_resident_context(initialization: Dictionary) -> String:
	if not initialization.has("me"):
		return ""
	var me := initialization.get("me", {}) as Dictionary
	var resident_id := String(me.get("resident_id", "")).strip_edges()
	if resident_id.is_empty():
		return ""
	# Existing character-card data is the fallback source, so every resident
	# receives a stable persona even before a dedicated user override is saved.
	return _persona.build_prompt(resident_id, initialization)


func get_base_system_prompt() -> String:
	return _base_system_prompt


func inject(base_prompt: String, initialization: Dictionary) -> String:
	var layers: Array[String] = []
	_append_global_layer(layers)
	if not base_prompt.strip_edges().is_empty():
		layers.append(
			"<ai_town_runtime_prompt>\n%s\n</ai_town_runtime_prompt>"
			% base_prompt.strip_edges()
		)
	layers.append(PromptPolicyScript.text())
	var persona_prompt := build_resident_context(initialization)
	if not persona_prompt.is_empty():
		layers.append(persona_prompt.strip_edges())
	return "\n\n".join(layers)


func build_preview(resident_id: String, custom_prompt: String = "") -> String:
	# UI preview intentionally shows stable assembled layers only. The real
	# runtime contract and current event/memory are request-specific and are
	# represented by explicit placeholders instead of fabricated data.
	var profile: Dictionary = {}
	var normalized_id := resident_id.strip_edges()
	if not normalized_id.is_empty():
		profile = _persona.get_profile(normalized_id)
	if not custom_prompt.strip_edges().is_empty() or profile.has("custom_prompt"):
		profile["custom_prompt"] = PromptBudgetScript.trim_profile_field(
			"custom_prompt",
			custom_prompt,
		)

	var layers: Array[String] = []
	_append_global_layer(layers)
	layers.append(
		"<ai_town_runtime_prompt>\n"
		+ "[运行时注入：世界事实、合法动作、输出格式与当前模拟合同]\n"
		+ "</ai_town_runtime_prompt>"
	)
	layers.append(PromptPolicyScript.text())
	var persona_prompt := _persona.build_prompt_from_profile(profile)
	if not persona_prompt.is_empty():
		layers.append(persona_prompt)
	layers.append(
		"<dynamic_context>\n"
		+ "[运行时注入：当前事件、附近人物、近期记忆与可执行动作]\n"
		+ "</dynamic_context>"
	)
	return "\n\n".join(layers)


func _append_global_layer(layers: Array[String]) -> void:
	if _base_system_prompt.strip_edges().is_empty():
		return
	layers.append(
		"<global_system_prompt>\n%s\n</global_system_prompt>"
		% _base_system_prompt.strip_edges()
	)


func _load_base_system_prompt() -> String:
	if not FileAccess.file_exists(BASE_SYSTEM_PROMPT_PATH):
		return ""
	var file := FileAccess.open(BASE_SYSTEM_PROMPT_PATH, FileAccess.READ)
	if file == null:
		return ""
	return PromptBudgetScript.trim_base_system_prompt(file.get_as_text())
