class_name UnlimitedModeDialog
extends Control


signal save_requested(payload: Dictionary)

const PROMPT_MAX_LENGTH := 12000

var _provider_id := ""
var _mode: OptionButton
var _persona: OptionButton
var _custom_prompt: TextEdit
var _runtime_prompt: TextEdit
var _model_fallback: CheckBox
var _memory_extraction: CheckBox
var _continuity_analysis: CheckBox
var _error_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 1100
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build_interface()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		visible = false
		get_viewport().set_input_as_handled()


func configure(provider_id: String, options: Dictionary) -> void:
	_provider_id = provider_id
	_mode.select(1 if bool(options.get("enabled", false)) else 0)
	_persona.select(
		1 if String(options.get("personaMode", "builtin")) == "custom" else 0
	)
	_custom_prompt.text = String(options.get("customPrompt", ""))
	_runtime_prompt.text = String(options.get("runtimePrompt", ""))
	_model_fallback.button_pressed = bool(options.get("modelFallback", true))
	_memory_extraction.button_pressed = bool(options.get("memoryExtraction", true))
	_continuity_analysis.button_pressed = bool(
		options.get("continuityAnalysis", true)
	)
	_error_label.text = ""
	_sync_persona_editor()


func popup_centered() -> void:
	visible = true
	move_to_front()
	_mode.grab_focus.call_deferred()


func _build_interface() -> void:
	if _mode != null:
		return
	var veil := ColorRect.new()
	veil.name = "ModalVeil"
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color("11140fd9")
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(veil)

	var center := CenterContainer.new()
	center.name = "DialogCenter"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 24
	center.offset_top = 24
	center.offset_right = -24
	center.offset_bottom = -24
	add_child(center)

	var panel := PanelContainer.new()
	panel.name = "UnlimitedModePanel"
	panel.custom_minimum_size = Vector2(900, 650)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("f7edcf")
	panel_style.border_color = Color("6c4829")
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(16)
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)

	var title := _label("Unlimited AI 增强模式", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	var explanation := _label(
		"普通模式保持 AI Town 原有决策链；增强模式接入 context.js、prompts.js、"
		+ "MODEL_RUNTIME_INJECTION、人物模式、模型自动切换、记忆提取与连续性分析。",
		18,
	)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.custom_minimum_size.y = 50
	content.add_child(explanation)

	_mode = _option_row(content, "运行模式")
	_mode.add_item("普通 AI Town 模式")
	_mode.add_item("Unlimited AI 增强模式")

	_persona = _option_row(content, "人物 Prompt")
	_persona.add_item("😈 原版内置 prompts.js")
	_persona.add_item("😇 自定义人物 Prompt")
	_persona.item_selected.connect(func(_index: int) -> void:
		_sync_persona_editor()
	)

	content.add_child(_label("自定义人物 Prompt（仅 😇 模式使用）", 18))
	_custom_prompt = _text_editor(
		"填写适合居民决策的 Prompt；保存时最多 12000 个字符。",
		105,
	)
	content.add_child(_custom_prompt)

	content.add_child(_label("运行 Prompt", 18))
	_runtime_prompt = _text_editor(
		"留空时使用原版 MODEL_RUNTIME_INJECTION；无论如何都会追加 AI Town 严格 JSON 决策合同。",
		105,
	)
	content.add_child(_runtime_prompt)

	var checks := GridContainer.new()
	checks.columns = 2
	checks.add_theme_constant_override("h_separation", 28)
	checks.add_theme_constant_override("v_separation", 6)
	_model_fallback = _check("模型失败时自动切换")
	_memory_extraction = _check("提取长期记忆")
	_continuity_analysis = _check("检查人物与世界连续性")
	var context_check := _check("context.js 上下文整理（始终接入）")
	context_check.button_pressed = true
	context_check.disabled = true
	checks.add_child(_model_fallback)
	checks.add_child(_memory_extraction)
	checks.add_child(_continuity_analysis)
	checks.add_child(context_check)
	content.add_child(checks)

	_error_label = _label("", 16)
	_error_label.add_theme_color_override("font_color", Color("a52a2a"))
	_error_label.custom_minimum_size.y = 24
	content.add_child(_error_label)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 12)
	var cancel := Button.new()
	cancel.text = "取消"
	cancel.custom_minimum_size = Vector2(130, 48)
	cancel.pressed.connect(func() -> void:
		visible = false
	)
	actions.add_child(cancel)
	var save := Button.new()
	save.text = "保存模式设置"
	save.custom_minimum_size = Vector2(190, 48)
	save.pressed.connect(_submit)
	actions.add_child(save)
	content.add_child(actions)


func _option_row(parent: VBoxContainer, label_text: String) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var label := _label(label_text, 18)
	label.custom_minimum_size.x = 180
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.custom_minimum_size.y = 42
	row.add_child(option)
	parent.add_child(row)
	return option


func _label(value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("3f2818"))
	return label


func _text_editor(placeholder: String, minimum_height: float) -> TextEdit:
	var editor := TextEdit.new()
	editor.placeholder_text = placeholder
	editor.custom_minimum_size.y = minimum_height
	editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	editor.add_theme_font_size_override("font_size", 16)
	return editor


func _check(value: String) -> CheckBox:
	var check := CheckBox.new()
	check.text = value
	check.add_theme_font_size_override("font_size", 17)
	return check


func _sync_persona_editor() -> void:
	if _custom_prompt == null:
		return
	_custom_prompt.editable = _persona.selected == 1
	_custom_prompt.modulate = Color.WHITE if _custom_prompt.editable else Color("ffffff88")


func _submit() -> void:
	var custom_prompt := _custom_prompt.text
	var runtime_prompt := _runtime_prompt.text
	if custom_prompt.length() > PROMPT_MAX_LENGTH or runtime_prompt.length() > PROMPT_MAX_LENGTH:
		_error_label.text = "单个 Prompt 不能超过 12000 个字符。"
		return
	if _persona.selected == 1 and custom_prompt.strip_edges().is_empty():
		_error_label.text = "选择 😇 自定义人物模式时，请填写人物 Prompt。"
		_custom_prompt.grab_focus()
		return
	_error_label.text = ""
	visible = false
	save_requested.emit({
		"providerId": _provider_id,
		"enabled": _mode.selected == 1,
		"personaMode": "custom" if _persona.selected == 1 else "builtin",
		"customPrompt": custom_prompt,
		"runtimePrompt": runtime_prompt,
		"modelFallback": _model_fallback.button_pressed,
		"memoryExtraction": _memory_extraction.button_pressed,
		"continuityAnalysis": _continuity_analysis.button_pressed,
	})
