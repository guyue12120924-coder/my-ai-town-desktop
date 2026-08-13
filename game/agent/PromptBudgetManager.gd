class_name AgentPromptBudgetManager
extends RefCounted

## Conservative character-based budgets for optional prompt layers.
## Provider context windows vary, so this class does not truncate the core
## AI Town system contract. It bounds user-editable persona fields and the
## optional memory/retry payloads before they are compiled into a request.

const MEMORY_PROMPT_MAX_CHARS := 12000
const RETRY_FEEDBACK_MAX_CHARS := 3000
const BASE_SYSTEM_PROMPT_MAX_CHARS := 8000

const PROFILE_FIELD_LIMITS := {
	"name": 120,
	"personality": 1600,
	"background": 2200,
	"goals": 1600,
	"speaking_style": 1600,
	"behavior_rules": 2800,
	"custom_prompt": 8000,
	"long_term_memory": 6000,
	"relationship_notes": 4000,
}


static func trim_profile_field(field: String, text: String) -> String:
	var normalized := text.strip_edges()
	var maximum := int(PROFILE_FIELD_LIMITS.get(field, 2000))
	return _trim_tail(
		normalized,
		maximum,
		"\n[内容因 Prompt 预算已截断]",
	)


static func trim_memory_prompt(text: String) -> String:
	return _trim_middle(
		text.strip_edges(),
		MEMORY_PROMPT_MAX_CHARS,
		"\n[较早的记忆内容因上下文预算被省略]\n",
	)


static func trim_retry_feedback(text: String) -> String:
	return _trim_tail(
		text.strip_edges(),
		RETRY_FEEDBACK_MAX_CHARS,
		"\n[重试反馈因上下文预算已截断]",
	)


static func trim_base_system_prompt(text: String) -> String:
	return _trim_tail(
		text.strip_edges(),
		BASE_SYSTEM_PROMPT_MAX_CHARS,
		"\n[全局 Prompt 超过安全预算，后续内容未注入]",
	)


static func estimate_tokens(text: String) -> int:
	# Deliberately conservative for mixed Chinese/English text. Tokenizers vary,
	# so this is a UI/debug indicator and never a provider billing value.
	if text.is_empty():
		return 0
	return int(ceil(float(text.length()) / 2.0))


static func _trim_tail(text: String, maximum: int, marker: String) -> String:
	if text.length() <= maximum:
		return text
	if maximum <= marker.length():
		return text.left(maximum)
	var available := maximum - marker.length()
	return text.left(available).strip_edges() + marker


static func _trim_middle(text: String, maximum: int, marker: String) -> String:
	if text.length() <= maximum:
		return text
	var available := maximum - marker.length()
	if available <= 32:
		return text.left(maximum)
	var head_chars := int(floor(float(available) * 0.25))
	var tail_chars := available - head_chars
	var tail_start := maxi(0, text.length() - tail_chars)
	return (
		text.left(head_chars).strip_edges()
		+ marker
		+ text.substr(tail_start, tail_chars).strip_edges()
	)
