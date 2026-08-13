class_name ResidentPromptTemplateLibrary
extends RefCounted

const TEMPLATE_PATH := "res://prompts/resident_prompt_templates.json"


static func templates() -> Array:
	if not FileAccess.file_exists(TEMPLATE_PATH):
		return []
	var file := FileAccess.open(TEMPLATE_PATH, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	var values: Variant = (parsed as Dictionary).get("templates", [])
	if typeof(values) != TYPE_ARRAY:
		return []
	var result: Array = []
	for value: Variant in values:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var template := value as Dictionary
		var template_id := String(template.get("id", "")).strip_edges()
		var label := String(template.get("label", "")).strip_edges()
		var content := String(template.get("content", "")).strip_edges()
		if template_id.is_empty() or label.is_empty() or content.is_empty():
			continue
		result.append({
			"id": template_id,
			"label": label,
			"description": String(template.get("description", "")).strip_edges(),
			"content": content,
		})
	return result
