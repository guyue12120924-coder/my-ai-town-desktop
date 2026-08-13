extends SceneTree


const PersonaProfileScript := preload("res://agent/ResidentPersonaProfile.gd")
const TEST_ID := "resident-persona-history-sync-test"

var _failed := 0


func _initialize() -> void:
	var writer: RefCounted = PersonaProfileScript.new()
	writer.call("remove_profile", TEST_ID)
	var reader: RefCounted = PersonaProfileScript.new()

	var first := {
		"name": "测试居民",
		"custom_prompt": "第一版：保持谨慎。",
	}
	var first_result := writer.call("set_profile", TEST_ID, first) as Dictionary
	_expect(bool(first_result.get("ok", false)), "第一版角色 Prompt 保存成功")
	var reader_first := reader.call("get_profile", TEST_ID) as Dictionary
	_expect(
		String(reader_first.get("custom_prompt", "")) == "第一版：保持谨慎。",
		"已经存在的另一个 Profile 实例立即看到新 Prompt",
	)

	var second := first.duplicate(true)
	second["custom_prompt"] = "第二版：谨慎但更愿意帮助熟人。"
	var second_result := writer.call("set_profile", TEST_ID, second) as Dictionary
	_expect(bool(second_result.get("ok", false)), "第二版角色 Prompt 保存成功")
	var reader_second := reader.call("get_profile", TEST_ID) as Dictionary
	_expect(
		String(reader_second.get("custom_prompt", "")) == "第二版：谨慎但更愿意帮助熟人。",
		"同一进程内 Prompt 更新不依赖文件时间粒度",
	)

	var history := writer.call("get_history", TEST_ID) as Array
	_expect(history.size() >= 1, "角色 Prompt 修改会保留历史快照")
	if not history.is_empty():
		var restore_result := writer.call("restore_history", TEST_ID, history.size() - 1) as Dictionary
		_expect(bool(restore_result.get("ok", false)), "角色 Prompt 历史版本可以恢复")
		var restored := reader.call("get_profile", TEST_ID) as Dictionary
		_expect(
			String(restored.get("custom_prompt", "")) == "第一版：保持谨慎。",
			"恢复历史后其他实例立即读取到旧版本",
		)

	var cleared := reader.call("get_profile", TEST_ID) as Dictionary
	cleared["custom_prompt"] = ""
	var clear_result := writer.call("set_profile", TEST_ID, cleared) as Dictionary
	_expect(bool(clear_result.get("ok", false)), "角色 Prompt 可以明确清空")
	var prompt_after_clear := String(writer.call(
		"build_prompt",
		TEST_ID,
		{
			"me": {
				"resident_id": TEST_ID,
				"attributes": {
					"name": "测试居民",
					"custom_prompt": "初始化阶段遗留的旧 Prompt",
				},
			},
		},
	))
	_expect(
		not prompt_after_clear.contains("初始化阶段遗留的旧 Prompt"),
		"用户清空 Prompt 后初始化旧值不会重新出现",
	)
	_expect(
		String((reader.call("get_profile", TEST_ID) as Dictionary).get("custom_prompt", "")) == "",
		"清空结果会立即同步到已有 Profile 实例",
	)

	writer.call("remove_profile", TEST_ID)
	if _failed == 0:
		print("RESIDENT_PERSONA_HISTORY_PASS")
		quit(0)
	else:
		printerr("RESIDENT_PERSONA_HISTORY_FAIL count=%d" % _failed)
		quit(1)


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failed += 1
	printerr("[FAIL] %s" % label)
