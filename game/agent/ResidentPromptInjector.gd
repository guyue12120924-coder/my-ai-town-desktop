class_name ResidentPromptInjector
extends RefCounted

const PersonaProfileScript := preload("res://agent/ResidentPersonaProfile.gd")

var _persona: PersonaProfileScript


func _init() -> void:
	_persona = PersonaProfileScript.new()


func build_resident_context(initialization: Dictionary) -> String:
	if not initialization.has("me"):
		return ""
	var me := initialization.get("me", {}) as Dictionary
	var resident_id := String(me.get("resident_id", "")).strip_edges()
	if resident_id.is_empty():
		return ""
	# The live initialization is the fallback source, so every resident created
	# from the existing character-card UI receives a persona even when no manual
	# user:// override exists. User profile values take priority in the store.
	return _persona.build_prompt(resident_id, initialization)


func inject(base_prompt: String, initialization: Dictionary) -> String:
	var persona_prompt := build_resident_context(initialization)
	if persona_prompt.is_empty():
		return base_prompt
	return "%s\n\n%s" % [base_prompt.rstrip("\n"), persona_prompt.strip_edges()]
