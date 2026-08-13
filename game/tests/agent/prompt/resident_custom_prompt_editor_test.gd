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
	_expect(prompt_edit != null, "角色 Prompt 弹窗包含多行编辑框")
	_expect(save_button != null, "角色 Prompt 弹窗包含保存按钮")
	if prompt_edit == null or save_button == null:
		_finish(page, store)
		return

	prompt_edit.text = "只相信亲眼确认的事实；面对陌生人先观察，再决定是否提供帮助。"
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
		page.queue_free()
	await process_frame
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
