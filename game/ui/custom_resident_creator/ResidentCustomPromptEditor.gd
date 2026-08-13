class_name ResidentCustomPromptEditor
extends Control


const PersonaProfileScript := preload("res://agent/ResidentPersonaProfile.gd")
const PromptInjectorScript := preload("res://agent/ResidentPromptInjector.gd")
const PromptTemplateLibraryScript := preload("res://agent/ResidentPromptTemplateLibrary.gd")
const PromptBudgetScript := preload("res://agent/PromptBudgetManager.gd")
const PROMPT_MAX_LENGTH := 8000

var _page: Control
var _profile_store: PersonaProfileScript
var _prompt_injector: ResidentPromptInjector
var _templates: Array = []
var _pending_prompt := ""
var _button: Button
var _overlay: ColorRect
var _prompt_edit: TextEdit
var _status_label: Label
var _counter_label: Label
var _template_option: OptionButton
var _history_option: OptionButton
var _restore_history_button: Button
var _preview_overlay: ColorRect
var _preview_text: TextEdit
var _preview_meta_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 250
	_profile_store = PersonaProfileScript.new()
	_prompt_injector = PromptInjectorScript.new()
	_templates = PromptTemplateLibraryScript.templates()
	call_deferred("_attach_to_page")


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	# Consume Escape before the parent page's _unhandled_input() can interpret it
	# as "leave the resident screen" while a modal Prompt layer is open.
	if is_instance_valid(_preview_overlay) and _preview_overlay.visible:
		_preview_overlay.visible = false
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(_overlay) and _overlay.visible:
		_close_editor()
		get_viewport().set_input_as_handled()


func _attach_to_page() -> void:
	_page = get_parent() as Control
	if _page == null:
		return
	_build_button()
	_build_overlay()
	_build_preview_overlay()
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
	panel.offset_left = -410.0
	panel.offset_top = -380.0
	panel.offset_right = 410.0
	panel.offset_bottom = 380.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)

	var title := Label.new()
	title.text = "角色专属 Prompt"
	title.add_theme_font_size_override("font_size", 28)
	content.add_child(title)

	var hint := Label.new()
	hint.text = (
		"这里的内容只作用于当前角色，会与性格、欲望、说话方式一起进入模型。"
		+ "角色 Prompt 不能覆盖世界事实、可执行动作、输出合同或更高优先级规则。"
	)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(750, 52)
	content.add_child(hint)

	var template_row := HBoxContainer.new()
	template_row.name = "ResidentPromptTemplateRow"
	template_row.add_theme_constant_override("separation", 10)
	_template_option = OptionButton.new()
	_template_option.name = "ResidentPromptTemplateOption"
	_template_option.custom_minimum_size = Vector2(420, 44)
	_template_option.add_item("选择 Prompt 模板（可选）")
	for template_value: Variant in _templates:
		var template := template_value as Dictionary
		_template_option.add_item(String(template.get("label", "未命名模板")))
		_template_option.set_item_tooltip(
			_template_option.item_count - 1,
			String(template.get("description", "")),
		)
	template_row.add_child(_template_option)

	var insert_template_button := Button.new()
	insert_template_button.name = "ResidentPromptInsertTemplateButton"
	insert_template_button.text = "插入模板"
	insert_template_button.custom_minimum_size = Vector2(120, 44)
	insert_template_button.pressed.connect(_apply_selected_template)
	template_row.add_child(insert_template_button)

	var preview_button := Button.new()
	preview_button.name = "ResidentPromptPreviewButton"
	preview_button.text = "预览组合 Prompt"
	preview_button.custom_minimum_size = Vector2(172, 44)
	preview_button.pressed.connect(_open_preview)
	template_row.add_child(preview_button)
	content.add_child(template_row)

	var history_row := HBoxContainer.new()
	history_row.name = "ResidentPromptHistoryRow"
	history_row.add_theme_constant_override("separation", 10)
	_history_option = OptionButton.new()
	_history_option.name = "ResidentPromptHistoryOption"
	_history_option.custom_minimum_size = Vector2(570, 42)
	_history_option.add_item("历史版本（保存后自动记录，最多 20 个）")
	_history_option.item_selected.connect(_on_history_selected)
	history_row.add_child(_history_option)
	_restore_history_button = Button.new()
	_restore_history_button.name = "ResidentPromptRestoreHistoryButton"
	_restore_history_button.text = "恢复所选版本"
	_restore_history_button.custom_minimum_size = Vector2(172, 42)
	_restore_history_button.disabled = true
	_restore_history_button.pressed.connect(_restore_selected_history)
	history_row.add_child(_restore_history_button)
	content.add_child(history_row)

	_prompt_edit = TextEdit.new()
	_prompt_edit.name = "ResidentCustomPromptEdit"
	_prompt_edit.custom_minimum_size = Vector2(750, 250)
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


func _build_preview_overlay() -> void:
	if is_instance_valid(_preview_overlay):
		return
	_preview_overlay = ColorRect.new()
	_preview_overlay.name = "ResidentPromptPreviewOverlay"
	_preview_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_overlay.color = Color(0.035, 0.03, 0.025, 0.84)
	_preview_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_preview_overlay.z_index = 1100
	_preview_overlay.visible = false
	add_child(_preview_overlay)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -500.0
	panel.offset_top = -410.0
	panel.offset_right = 500.0
	panel.offset_bottom = 410.0
	_preview_overlay.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)

	var title := Label.new()
	title.text = "Prompt 组合预览"
	title.add_theme_font_size_override("font_size", 26)
	content.add_child(title)

	var hint := Label.new()
	hint.text = "这里展示稳定 Prompt 层。世界状态、近期记忆和可执行动作会在每次真实请求时动态注入，因此以占位符显示。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(hint)

	_preview_meta_label = Label.new()
	_preview_meta_label.name = "ResidentPromptPreviewMeta"
	content.add_child(_preview_meta_label)

	_preview_text = TextEdit.new()
	_preview_text.name = "ResidentPromptPreviewText"
	_preview_text.custom_minimum_size = Vector2(930, 520)
	_preview_text.editable = false
	_preview_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	content.add_child(_preview_text)

	var close_button := Button.new()
	close_button.name = "ResidentPromptPreviewCloseButton"
	close_button.text = "关闭预览"
	close_button.custom_minimum_size = Vector2(140, 44)
	close_button.pressed.connect(func() -> void: _preview_overlay.visible = false)
	content.add_child(close_button)


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
	_refresh_history_options(resident_id)
	_update_counter()
	_overlay.visible = true
	_prompt_edit.grab_focus()


func _close_editor() -> void:
	if is_instance_valid(_preview_overlay):
		_preview_overlay.visible = false
	if is_instance_valid(_overlay):
		_overlay.visible = false


func _apply_selected_template() -> void:
	if not is_instance_valid(_template_option) or not is_instance_valid(_prompt_edit):
		return
	var selected := _template_option.selected
	if selected <= 0 or selected - 1 >= _templates.size():
		_set_status("请先选择一个 Prompt 模板。")
		return
	var template := _templates[selected - 1] as Dictionary
	var template_content := String(template.get("content", "")).strip_edges()
	if template_content.is_empty():
		return
	var current := _prompt_edit.text.strip_edges()
	_prompt_edit.text = (
		template_content
		if current.is_empty()
		else current + "\n\n" + template_content
	)
	_prompt_edit.set_caret_line(maxi(0, _prompt_edit.get_line_count() - 1))
	_update_counter()
	_set_status("已插入模板：%s，可继续自由修改。" % String(template.get("label", "")))


func _refresh_history_options(resident_id: String) -> void:
	if not is_instance_valid(_history_option) or not is_instance_valid(_restore_history_button):
		return
	_history_option.clear()
	_history_option.add_item("历史版本（保存后自动记录，最多 20 个）")
	_restore_history_button.disabled = true
	var normalized_id := resident_id.strip_edges()
	if normalized_id.is_empty():
		return
	var history := _profile_store.get_history(normalized_id)
	for reverse_offset: int in history.size():
		var history_index := history.size() - 1 - reverse_offset
		_history_option.add_item("Prompt 历史版本 %d（越靠上越新）" % (reverse_offset + 1))
		_history_option.set_item_metadata(
			_history_option.item_count - 1,
			history_index,
		)


func _on_history_selected(index: int) -> void:
	if is_instance_valid(_restore_history_button):
		_restore_history_button.disabled = index <= 0


func _restore_selected_history() -> void:
	if (
		not is_instance_valid(_history_option)
		or not is_instance_valid(_prompt_edit)
		or _history_option.selected <= 0
	):
		return
	var resident_id := _current_resident_id()
	if resident_id.is_empty():
		_set_status("新角色尚未创建，没有可恢复的历史版本。")
		return
	var history := _profile_store.get_history(resident_id)
	var history_index := int(_history_option.get_item_metadata(_history_option.selected))
	if history_index < 0 or history_index >= history.size():
		_set_status("所选历史版本已经失效，请重新打开窗口。")
		return
	var entry_value: Variant = history[history_index]
	if typeof(entry_value) != TYPE_DICTIONARY:
		_set_status("所选历史版本损坏。")
		return
	var historical_profile_value: Variant = (entry_value as Dictionary).get("profile", {})
	if typeof(historical_profile_value) != TYPE_DICTIONARY:
		_set_status("所选历史版本损坏。")
		return
	var historical_prompt := String(
		(historical_profile_value as Dictionary).get("custom_prompt", ""),
	).strip_edges()
	var current_profile := _profile_store.get_profile(resident_id)
	current_profile["custom_prompt"] = historical_prompt
	var result := _profile_store.set_profile(resident_id, current_profile)
	if not bool(result.get("ok", false)):
		_set_status("历史版本恢复失败。")
		return
	_prompt_edit.text = historical_prompt
	_update_counter()
	_refresh_history_options(resident_id)
	_set_status("已恢复所选 Prompt 历史版本；恢复前版本也已保留。")


func _open_preview() -> void:
	if (
		not is_instance_valid(_preview_overlay)
		or not is_instance_valid(_preview_text)
		or not is_instance_valid(_prompt_edit)
	):
		return
	var preview := _prompt_injector.build_preview(
		_current_resident_id(),
		_prompt_edit.text,
		_current_profile_override(),
	)
	_preview_text.text = preview
	_preview_text.set_caret_line(0)
	_preview_text.set_caret_column(0)
	_preview_meta_label.text = "稳定层字符数：%d；粗略 Token 估算：约 %d（仅调试参考）" % [
		preview.length(),
		PromptBudgetScript.estimate_tokens(preview),
	]
	_preview_overlay.visible = true


func _current_profile_override() -> Dictionary:
	if _page == null or not _page.has_method("current_view_model"):
		return {}
	var view_model := _page.call("current_view_model") as Dictionary
	var data := view_model.get("data", {}) as Dictionary
	var draft := data.get("draft", {}) as Dictionary
	var result: Dictionary = {}
	_copy_preview_field(result, "name", draft.get("name", ""))
	_copy_preview_field(result, "personality", draft.get("personality", ""))
	_copy_preview_field(result, "goals", draft.get("desire", ""))
	_copy_preview_field(result, "speaking_style", draft.get("speech", ""))
	return result


func _copy_preview_field(target: Dictionary, field: String, value: Variant) -> void:
	var text := String(value).strip_edges()
	if not text.is_empty():
		target[field] = text


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
	_refresh_history_options(normalized_id)
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
