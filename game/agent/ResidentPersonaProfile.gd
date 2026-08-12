class_name ResidentPersonaProfile
extends RefCounted

## Resident persona prompt profile loader.
## Keeps character identity separate from model/provider logic.

const PROFILE_PATH := "res://residents/resident_profiles.json"

var _profiles: Dictionary = {}

func _init() -> void:
	_load_profiles()


func _load_profiles() -> void:
	if not FileAccess.file_exists(PROFILE_PATH):
		return
	var file := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	if file == null:
		return
	var data = JSON.parse_string(file.get_as_text())
	if typeof(data) == TYPE_DICTIONARY:
		_profiles = data.get("residents", {}).duplicate(true)


func get_profile(resident_id: String) -> Dictionary:
	if not _profiles.has(resident_id):
		return {}
	return (_profiles[resident_id] as Dictionary).duplicate(true)


func build_prompt(resident_id: String) -> String:
	var profile := get_profile(resident_id)
	if profile.is_empty():
		return ""

	return """
Character Profile:
Name: %s
Personality: %s
Background: %s
Goals: %s
Speaking Style: %s
Behavior Rules: %s
Long Term Memory: %s
""" % [
		profile.get("name", ""),
		profile.get("personality", ""),
		profile.get("background", ""),
		profile.get("goals", ""),
		profile.get("speaking_style", ""),
		profile.get("behavior_rules", ""),
		profile.get("long_term_memory", ""),
	]
