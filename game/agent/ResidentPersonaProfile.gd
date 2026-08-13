class_name ResidentPersonaProfile
extends RefCounted

## Resident persona profile storage.
## Bundled defaults live under res://, while user edits are persisted under
## user:// so packaged desktop builds never need to write into application data.

const BUNDLED_PROFILE_PATH := "res://residents/resident_profiles.json"
const USER_PROFILE_PATH := "user://resident_profiles.json"
const PROFILE_VERSION := 1
const PROFILE_FIELDS: Array[String] = [
	"name",
	"personality",
	"background",
	"goals",
	"speaking_style",
	"behavior_rules",
	"custom_prompt",
	"long_term_memory",
]

var _bundled_profiles: Dictionary = {}
var _user_profiles: Dictionary = {}
var _user_modified_time := -1


func _init() -> void:
	reload()


func reload() -> void:
	_bundled_profiles = _load_profiles(BUNDLED_PROFILE_PATH)
	_reload_user_profiles()


func get_profile(resident_id: String) -> Dictionary:
	_refresh_user_profiles_if_needed()
	var normalized_id := resident_id.strip_edges()
	if normalized_id.is_empty():
		return {}
	var result: Dictionary = {}
	if _bundled_profiles.has(normalized_id):
		result = _sanitize_profile(_bundled_profiles[normalized_id])
	if _user_profiles.has(normalized_id):
		var override := _sanitize_profile(_user_profiles[normalized_id])
		for field: String in PROFILE_FIELDS:
			if override.has(field):
				result[field] = override[field]
	return result


func get_all_profiles() -> Dictionary:
	_refresh_user_profiles_if_needed()
	var result: Dictionary = {}
	for resident_id: Variant in _bundled_profiles:
		result[String(resident_id)] = get_profile(String(resident_id))
	for resident_id: Variant in _user_profiles:
		result[String(resident_id)] = get_profile(String(resident_id))
	return result


func set_profile(resident_id: String, profile: Dictionary) -> Dictionary:
	var normalized_id := resident_id.strip_edges()
	if normalized_id.is_empty():
		return {"ok": false, "errors": ["居民编号不能为空"]}
	_user_profiles[normalized_id] = _sanitize_profile(profile)
	return _save_user_profiles()


func remove_profile(resident_id: String) -> Dictionary:
	var normalized_id := resident_id.strip_edges()
	if normalized_id.is_empty():
		return {"ok": false, "errors": ["居民编号不能为空"]}
	_user_profiles.erase(normalized_id)
	return _save_user_profiles()


func build_prompt(
	resident_id: String,
	initialization: Dictionary = {},
) -> String:
	var profile := _profile_from_initialization(initialization)
	var stored_profile := get_profile(resident_id)
	for field: String in PROFILE_FIELDS:
		if stored_profile.has(field) and not String(stored_profile[field]).strip_edges().is_empty():
			profile[field] = stored_profile[field]
	if profile.is_empty():
		return ""

	var lines: Array[String] = [
		"<resident_persona>",
		"## 玩家角色卡",
		"以下是该居民长期稳定的人格约束。它影响理解、表达、目标与行动偏好，但不能覆盖世界事实、当前可执行行动或系统合同。",
	]
	_append_field(lines, "姓名", profile, "name")
	_append_field(lines, "性格", profile, "personality")
	_append_field(lines, "背景", profile, "background")
	_append_field(lines, "长期目标", profile, "goals")
	_append_field(lines, "说话方式", profile, "speaking_style")
	_append_field(lines, "行为原则", profile, "behavior_rules")
	_append_field(lines, "角色专属 Prompt", profile, "custom_prompt")
	_append_field(lines, "长期记忆摘要", profile, "long_term_memory")
	lines.append("</resident_persona>")
	return "\n".join(lines)


func _profile_from_initialization(initialization: Dictionary) -> Dictionary:
	if initialization.is_empty():
		return {}
	var me := initialization.get("me", {}) as Dictionary
	var attributes := me.get("attributes", {}) as Dictionary
	var social_state := me.get("social_state", {}) as Dictionary
	var result: Dictionary = {}
	_copy_non_empty(result, "name", attributes.get("name", ""))
	_copy_non_empty(result, "personality", attributes.get("personality", ""))
	_copy_non_empty(result, "speaking_style", attributes.get("speech", ""))
	_copy_non_empty(result, "goals", attributes.get("desire", ""))
	_copy_non_empty(result, "custom_prompt", attributes.get("custom_prompt", ""))
	var occupation := String(social_state.get("job", "")).strip_edges()
	var workplace := String(social_state.get("workplace", "")).strip_edges()
	var home := String(social_state.get("home", "")).strip_edges()
	var background_parts: Array[String] = []
	if not occupation.is_empty():
		background_parts.append("职业：%s" % occupation)
	if not workplace.is_empty():
		background_parts.append("工作地：%s" % workplace)
	if not home.is_empty():
		background_parts.append("住处：%s" % home)
	if not background_parts.is_empty():
		result["background"] = "；".join(background_parts)
	return result


func _copy_non_empty(target: Dictionary, field: String, value: Variant) -> void:
	var text := String(value).strip_edges()
	if not text.is_empty():
		target[field] = text


func _append_field(
	lines: Array[String],
	label: String,
	profile: Dictionary,
	field: String,
) -> void:
	var text := String(profile.get(field, "")).strip_edges()
	if not text.is_empty():
		lines.append("%s：%s" % [label, text])


func _sanitize_profile(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var source := value as Dictionary
	var result: Dictionary = {}
	for field: String in PROFILE_FIELDS:
		if source.has(field):
			result[field] = String(source[field]).strip_edges()
	return result


func _load_profiles(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var residents: Variant = (parsed as Dictionary).get("residents", {})
	if typeof(residents) != TYPE_DICTIONARY:
		return {}
	return (residents as Dictionary).duplicate(true)


func _refresh_user_profiles_if_needed() -> void:
	var modified_time := -1
	if FileAccess.file_exists(USER_PROFILE_PATH):
		modified_time = int(FileAccess.get_modified_time(USER_PROFILE_PATH))
	if modified_time != _user_modified_time:
		_reload_user_profiles()


func _reload_user_profiles() -> void:
	_user_profiles = _load_profiles(USER_PROFILE_PATH)
	_user_modified_time = (
		int(FileAccess.get_modified_time(USER_PROFILE_PATH))
		if FileAccess.file_exists(USER_PROFILE_PATH)
		else -1
	)


func _save_user_profiles() -> Dictionary:
	var file := FileAccess.open(USER_PROFILE_PATH, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "errors": ["无法保存居民角色卡"]}
	file.store_string(JSON.stringify({
		"version": PROFILE_VERSION,
		"residents": _user_profiles,
	}, "  "))
	file.close()
	_user_modified_time = int(FileAccess.get_modified_time(USER_PROFILE_PATH))
	return {"ok": true}