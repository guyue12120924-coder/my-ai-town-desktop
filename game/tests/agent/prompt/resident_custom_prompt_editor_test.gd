extends SceneTree


const PAGE_SCENE := preload(
	"res://ui/custom_resident_creator/CustomResidentCreatorScreen.tscn"
)
const PersonaProfileScript := preload("res://agent/ResidentPersonaProfile.gd")
const TEST_RESIDENT_ID := "resident-custom-prompt-editor-test"

var _failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var store: RefCounted = PersonaProfileScript.new()
	store.call("remove_profile", TEST_RESIDENT_ID)

	var page := PAGE_SCENE.instantiate() as Control
	root.add_child(page)
	await process_frame
	await process_frame

	var prompt_button := page.find_child(
		"ResidentCustomPromptButton",
		true,
		false,
	) as Button
	_expect(prompt_button != null, "角色页面挂载角色 Prompt 按钮")
	if prompt_button == null:
		_finish(page, store)
		return

	prompt_button.pressed.emit()
	await process_frame
	var prompt_edit := page.find_child(
		"ResidentCustomPromptEdit",
		true,
		false,
	) as TextEdit
	var save_button := page.find_child(
		"ResidentCustomPromptSaveButton",
		true,
		false,
	) as Button
	var template_option := page.find_child(
		"ResidentPromptTemplateOption",
		true,
		false,
	) as OptionButton
	var insert_template_button := page.find_child(
		"ResidentPromptInsertTemplateButton",
		true,
		false,
	) as Button
	var preview_button := page.find_child(
		"ResidentPromptPreviewButton",
		true,
		false,
	) as Button
	var history_option := page.find_child(
		"ResidentPromptHistoryOption",
		true,
		false,
	) as OptionButton
	var restore_history_button := page.find_child(
		"ResidentPromptRestoreHistoryButton",
		true,
		false,
	) as Button
	_expect(prompt_edit != null, "角色 Prompt 弹窗包含多行编辑框")
	_expect(save_button != null, "角色 Prompt 弹窗包含保存按钮")
	_expect(template_option != null, "角色 Prompt 弹窗提供模板选择")
	_expect(insert_template_button != null, "角色 Prompt 弹窗提供模板插入按钮")
	_expect(preview_button != null, "角色 Prompt 弹窗提供组合预览按钮")
	_expect(history_option != null, "角色 Prompt 弹窗提供历史版本选择")
	_expect(restore_history_button != null, "角色 Prompt 弹窗提供历史恢复按钮")
	if (
		prompt_edit == null
		or save_button == null
		or template_option == null
		or insert_template_button == null
		or preview_button == null
		or history_option == null
		or restore_history_button == null
	):
		_finish(page, store)
		return
	_expect(
		restore_history_button.disabled,
		"新角色尚无历史时恢复按钮保持禁用",
	)

	_expect(template_option.item_count > 1, "内置 Prompt 模板已成功加载")
	if template_option.item_count > 1:
		template_option.select(1)
		insert_template_button.pressed.emit()
		await process_frame
		_expect(not prompt_edit.text.strip_edges().is_empty(), "选择模板后内容写入编辑框")

	prompt_edit.text = "只相信亲眼确认的事实；面对陌生人先观察，再决定是否提供帮助。"
	preview_button.pressed.emit()
	await process_frame
	var preview_overlay := page.find_child(
		"ResidentPromptPreviewOverlay",
		true,
		false,
	) as ColorRect
	var preview_text := page.find_child(
		"ResidentPromptPreviewText",
		true,
		false,
	) as TextEdit
	_expect(preview_overlay != null and preview_overlay.visible, "组合 Prompt 预览可以打开")
	_expect(preview_text != null, "组合 Prompt 预览包含只读文本")
	if preview_text != null:
		_expect(preview_text.text.contains("<resident_prompt_policy>"), "预览显示角色优先级保护层")
		_expect(preview_text.text.contains("面对陌生人先观察"), "预览显示当前未保存角色 Prompt")
		_expect(preview_text.text.contains("[运行时注入：世界事实"), "动态世界上下文使用明确占位符")
	var close_preview := page.find_child(
		"ResidentPromptPreviewCloseButton",
		true,
		false,
	) as Button
	if close_preview != null:
		close_preview.pressed.emit()
		await process_frame

	save_button.pressed.emit()
	await process_frame

	page.intent_requested.emit(
		"custom_resident_creator.create",
		{
			"dispatchResult": {
				"ok": true,
				"selectionHandoff": {
					"focusedResidentId": TEST_RESIDENT_ID,
				},
			},
		},
	)
	await process_frame

	var reloaded: RefCounted = PersonaProfileScript.new()
	var profile := reloaded.call("get_profile", TEST_RESIDENT_ID) as Dictionary
	_expect(
		String(profile.get("custom_prompt", "")).contains("面对陌生人先观察"),
		"新角色创建成功后自动绑定并持久化独立 Prompt",
	)

	_finish(page, store)


func _finish(page: Control, store: RefCounted) -> void:
	store.call("remove_profile", TEST_RESIDENT_ID)
	if is_instance_valid(page):
		page.free()
	if _failed == 0:
		print("RESIDENT_CUSTOM_PROMPT_EDITOR_PASS")
		quit(0)
	else:
		printerr("RESIDENT_CUSTOM_PROMPT_EDITOR_FAIL count=%d" % _failed)
		quit(1)


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failed += 1
	printerr("[FAIL] %s" % label)
