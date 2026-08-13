class_name ResidentPromptInjector
extends RefCounted

const PersonaProfileScript := preload("res://agent/ResidentPersonaProfile.gd")
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
	if not _base_system_prompt.strip_edges().is_empty():
		layers.append(
			"<global_system_prompt>\n%s\n</global_system_prompt>"
			% _base_system_prompt.strip_edges()
		)
	if not base_prompt.strip_edges().is_empty():
		layers.append(
			"<ai_town_runtime_prompt>\n%s\n</ai_town_runtime_prompt>"
			% base_prompt.strip_edges()
		)
	var persona_prompt := build_resident_context(initialization)
	if not persona_prompt.is_empty():
		layers.append(persona_prompt.strip_edges())
	return "\n\n".join(layers)


func _load_base_system_prompt() -> String:
	if not FileAccess.file_exists(BASE_SYSTEM_PROMPT_PATH):
		return ""
	var file := FileAccess.open(BASE_SYSTEM_PROMPT_PATH, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text().strip_edges()