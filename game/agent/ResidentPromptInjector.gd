class_name ResidentPromptInjector
extends RefCounted

const PersonaProfileScript := preload("res://agent/ResidentPersonaProfile.gd")

var _persona: PersonaProfileScript

func _init() -> void:
	_persona = PersonaProfileScript.new()


func build_resident_context(initialization: Dictionary) -> String:
	if not initialization.has("me"):
		return ""

	var resident_id := String(initialization["me"].get("resident_id", ""))
	return _persona.build_prompt(resident_id)


func inject(base_prompt: String, initialization: Dictionary) -> String:
	var persona_prompt := build_resident_context(initialization)
	if persona_prompt.is_empty():
		return base_prompt

	return "%s\n\n%s" % [base_prompt, persona_prompt]
