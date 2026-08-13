class_name ResidentCustomPromptEditor
extends Control


const PersonaProfileScript := preload("res://agent/ResidentPersonaProfile.gd")
const PROMPT_MAX_LENGTH := 8000

var _page: Control
var _profile_store: PersonaProfileScript
var _pending_prompt := ""
var _button: Button
var _overlay: ColorRect
var _prompt_edit: TextEdit
var _status_label: Label
var _counter_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 250
	_profile_store = PersonaProfileScript.new()
	call_deferred("_attach_to_page")


func _attach_to_page() -> void:
	_page = get_parent() as Control
	if _page == null:
		return
	_build_button()
	_build_overlay()
	if _page.has_signal("intent_requested"):
		var callback := Callable(self, "_on_page_intent_requested")
		if not _page.is_connected("intent_requested", callback):
			_page.connect("intent_requested", callback)


func _build_button() -> void:
	if is_instance_valid(_button):
		return
	_button = Button.new()
	_button.name = "ResidentCustomPromptButton"
	_button.text = "角色 Prompt"
	_button.tooltip_text = "为当前角色设置独立的长期 Prompt"
	_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_button.offset_left = -202.0
	_button.offset_top = 24.0
	_button.offset_right = -34.0
	_button.offset_bottom = 70.0
	_button.focus_mode = Control.FOCUS_ALL
	_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_button.pressed.connect(_open_editor)
	add_child(_button)


func _build_overlay() -> void:
	if is_instance_valid(_overlay):
		return
	_overlay = ColorRect.new()
	_overlay.name = "ResidentCustomPromptOverlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.color = Color(0.06, 0.045, 0.03, 0.72)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.z_index = 1000
	_overlay.visible = false
	add_child(_overlay)

	var panel := PanelContainer.new()
	panel.name = "ResidentCustomPromptPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -390.0
	panel.offset_top = -285.0
	panel.offset_right = 390.0
	panel.offset_bottom = 285.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	margin.add_child(content)

	var title := Label.new()
	title.text = "角色专属 Prompt"
	title.add_theme_font_size_override("font_size", 28)
	content.add_child(title)

	var hint := Label.new()
	hint.text = (
		"这里的内容只作用于当前角色，会与性格、欲望、说话方式一起进入模型。"
		+ "它不能覆盖世界事实、可执行动作范围或 AI Town 的系统合同。"
	)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(710, 48)
	content.add_child(hint)

	_prompt_edit = TextEdit.new()
	_prompt_edit.name = "ResidentCustomPromptEdit"
	_prompt_edit.custom_minimum_size = Vector2(710, 340)
	_prompt_edit.placeholder_text = (
		"例如：面对陌生人的请求时先判断风险；不要为了迎合而轻易改变立场；"
		+ "对熟悉的人会更主动表达关心。"
	)
	_prompt_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_prompt_edit.text_changed.connect(_on_prompt_text_changed)
	content.add_child(_prompt_edit)

	var info_row := HBoxContainer.new()
	info_row.add_theme_constant_override("separation", 12)
	_status_label = Label.new()
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.text = ""
	info_row.add_child(_status_label)
	_counter_label = Label.new()
	_counter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info_row.add_child(_counter_label)
	content.add_child(info_row)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 12)
	var cancel_button := Button.new()
	cancel_button.name = "ResidentCustomPromptCancelButton"
	cancel_button.text = "取消"
	cancel_button.custom_minimum_size = Vector2(112, 44)
	cancel_button.pressed.connect(_close_editor)
	actions.add_child(cancel_button)
	var save_button := Button.new()
	save_button.name = "ResidentCustomPromptSaveButton"
	save_button.text = "保存 Prompt"
	save_button.custom_minimum_size = Vector2(142, 44)
	save_button.pressed.connect(_save_prompt)
	actions.add_child(save_button)
	content.add_child(actions)


func _open_editor() -> void:
	if not is_instance_valid(_overlay) or not is_instance_valid(_prompt_edit):
		return
	var resident_id := _current_resident_id()
	if resident_id.is_empty():
		_prompt_edit.text = _pending_prompt
		_set_status("新角色创建成功后会自动绑定到该角色。")
	else:
		var profile := _profile_store.get_profile(resident_id)
		_prompt_edit.text = String(profile.get("custom_prompt", ""))
		_set_status("当前角色：%s" % resident_id)
	_update_counter()
	_overlay.visible = true
	_prompt_edit.grab_focus()


func _close_editor() -> void:
	if is_instance_valid(_overlay):
		_overlay.visible = false


func _save_prompt() -> void:
	if not is_instance_valid(_prompt_edit):
		return
	var value := _prompt_edit.text.strip_edges()
	if value.length() > PROMPT_MAX_LENGTH:
		_set_status("Prompt 过长，请控制在 %d 个字符以内。" % PROMPT_MAX_LENGTH)
		return
	var resident_id := _current_resident_id()
	if resident_id.is_empty():
		_pending_prompt = value
		_set_status("已暂存；创建角色成功后会自动保存。")
		_close_editor()
		return
	if _persist_prompt(resident_id, value):
		_pending_prompt = ""
		_set_status("角色 Prompt 已保存。")
		_close_editor()


func _persist_prompt(resident_id: String, value: String) -> bool:
	var normalized_id := resident_id.strip_edges()
	if normalized_id.is_empty():
		return false
	var profile := _profile_store.get_profile(normalized_id)
	profile["custom_prompt"] = value
	var result := _profile_store.set_profile(normalized_id, profile)
	if not bool(result.get("ok", false)):
		var errors := result.get("errors", []) as Array
		_set_status(
			"保存失败：%s" % (
				"未知错误" if errors.is_empty() else String(errors[0])
			)
		)
		return false
	return true


func _current_resident_id() -> String:
	if _page == null or not _page.has_method("current_view_model"):
		return ""
	var view_model := _page.call("current_view_model") as Dictionary
	var data := view_model.get("data", {}) as Dictionary
	return String(data.get("residentId", "")).strip_edges()


func _on_page_intent_requested(intent: String, payload: Dictionary) -> void:
	if _pending_prompt.is_empty():
		return
	if intent != "custom_resident_creator.create":
		return
	var dispatch_result := payload.get("dispatchResult", {}) as Dictionary
	if not bool(dispatch_result.get("ok", false)):
		return
	var handoff := dispatch_result.get("selectionHandoff", {}) as Dictionary
	var resident_id := String(handoff.get("focusedResidentId", "")).strip_edges()
	if resident_id.is_empty():
		return
	if _persist_prompt(resident_id, _pending_prompt):
		_pending_prompt = ""


func _on_prompt_text_changed() -> void:
	_update_counter()
	if _prompt_edit.text.length() > PROMPT_MAX_LENGTH:
		_set_status("Prompt 超过 %d 个字符，保存前需要精简。" % PROMPT_MAX_LENGTH)


func _update_counter() -> void:
	if not is_instance_valid(_counter_label) or not is_instance_valid(_prompt_edit):
		return
	_counter_label.text = "%d / %d" % [
		_prompt_edit.text.length(),
		PROMPT_MAX_LENGTH,
	]


func _set_status(message: String) -> void:
	if is_instance_valid(_status_label):
		_status_label.text = message
