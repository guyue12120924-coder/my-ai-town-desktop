extends Node


const BRIDGE_HOST := "127.0.0.1"
const DEFAULT_BRIDGE_PORT := 19841
const RANDOM_PORT_START := 20000
const RANDOM_PORT_SPAN := 30000
const DISABLE_ENV := "AI_TOWN_DISABLE_DESKTOP_BRIDGE"
const HEALTH_RETRY_COUNT := 30
const HEALTH_RETRY_DELAY_SECONDS := 0.1

var _process_id := -1
var _launch_error := ""
var _launched_script_path := ""
var _bridge_ready := false
var _access_token := Crypto.new().generate_random_bytes(32).hex_encode()
var _bridge_port := _random_bridge_port()


func _ready() -> void:
	if (
		OS.has_feature("web")
		or DisplayServer.get_name() == "headless"
		or OS.get_environment(DISABLE_ENV) == "1"
	):
		return
	call_deferred("_launch_bridge")


func _exit_tree() -> void:
	_bridge_ready = false
	# 子进程通过 --parent-pid 监控 Godot，父进程结束后自行退出。
	# 不在这里按 PID 强杀：若桥提前退出且 PID 被系统复用，可能误伤无关进程。
	_process_id = -1


func status_snapshot() -> Dictionary:
	return {
		"processId": _process_id,
		"started": _process_id > 0,
		"ready": _bridge_ready,
		"error": _launch_error,
		"scriptPath": _launched_script_path,
		"endpoint": base_url(),
	}


static func base_url() -> String:
	if DisplayServer.get_name() == "headless":
		return "http://%s:%d/v1" % [BRIDGE_HOST, DEFAULT_BRIDGE_PORT]
	var bridge := _singleton()
	var port := (
		int(bridge.get("_bridge_port"))
		if bridge != null
		else DEFAULT_BRIDGE_PORT
	)
	return "http://%s:%d/v1" % [BRIDGE_HOST, port]


static func request_headers() -> PackedStringArray:
	var bridge := _singleton()
	if bridge == null:
		return PackedStringArray()
	var token := String(bridge.get("_access_token"))
	if token.is_empty():
		return PackedStringArray()
	return PackedStringArray(["X-AI-Town-Bridge-Token: %s" % token])


static func is_ready() -> bool:
	if DisplayServer.get_name() == "headless":
		return true
	var bridge := _singleton()
	return bridge != null and bool(bridge.get("_bridge_ready"))


static func _singleton() -> Node:
	var main_loop := Engine.get_main_loop()
	if not main_loop is SceneTree:
		return null
	return (main_loop as SceneTree).root.get_node_or_null(
		"SiliconFlowDesktopBridge",
	)


static func _random_bridge_port() -> int:
	var random_bytes := Crypto.new().generate_random_bytes(2)
	if random_bytes.size() != 2:
		return DEFAULT_BRIDGE_PORT
	return RANDOM_PORT_START + (random_bytes.decode_u16(0) % RANDOM_PORT_SPAN)


func _launch_bridge() -> void:
	if _process_id > 0:
		return
	var script_path := _bridge_script_path()
	if script_path.is_empty():
		_launch_error = "找不到 desktop_bridge/server.mjs"
		push_warning("硅基流动桌面桥未启动：%s" % _launch_error)
		return
	var node_executable := _node_executable()
	var arguments := PackedStringArray([
		script_path,
		"--port",
		str(_bridge_port),
		"--parent-pid",
		str(OS.get_process_id()),
		"--bridge-token",
		_access_token,
	])
	_process_id = OS.create_process(node_executable, arguments, false)
	_launched_script_path = script_path
	if _process_id <= 0:
		_launch_error = (
			"无法启动 Node.js。源码运行需安装 Node.js 20+；正式 Windows 包应包含 node.exe。"
		)
		push_warning("硅基流动桌面桥未启动：%s" % _launch_error)
		return
	_launch_error = ""
	_verify_bridge()


func _verify_bridge() -> void:
	for _attempt: int in range(HEALTH_RETRY_COUNT):
		var request := HTTPRequest.new()
		request.timeout = 2.0
		add_child(request)
		var error := request.request(
			"http://%s:%d/health" % [BRIDGE_HOST, _bridge_port],
			request_headers(),
			HTTPClient.METHOD_GET,
		)
		if error == OK:
			var response: Array = await request.request_completed
			var result_code := int(response[0])
			var status_code := int(response[1])
			var body := (response[3] as PackedByteArray).get_string_from_utf8()
			var parsed: Variant = JSON.parse_string(body)
			if (
				result_code == HTTPRequest.RESULT_SUCCESS
				and status_code == 200
				and parsed is Dictionary
				and (parsed as Dictionary).get("ok") == true
				and (parsed as Dictionary).get("service")
					== "ai-town-desktop-context-bridge"
			):
				request.queue_free()
				_bridge_ready = true
				return
		request.queue_free()
		await get_tree().create_timer(HEALTH_RETRY_DELAY_SECONDS).timeout
	_launch_error = "桌面上下文桥未通过本机身份检查；不会发送 API Key"
	push_warning("硅基流动桌面桥未启动：%s" % _launch_error)


func _bridge_script_path() -> String:
	var executable_directory := OS.get_executable_path().get_base_dir()
	var packaged := executable_directory.path_join(
		"desktop_bridge/server.mjs",
	)
	if FileAccess.file_exists(packaged):
		return packaged
	var project_directory := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var development := project_directory.get_base_dir().path_join(
		"desktop_bridge/server.mjs",
	)
	if FileAccess.file_exists(development):
		return development
	return ""


func _node_executable() -> String:
	var executable_directory := OS.get_executable_path().get_base_dir()
	var candidates: Array[String] = []
	if OS.get_name() == "Windows":
		candidates.append(executable_directory.path_join("node/node.exe"))
		candidates.append(
			executable_directory.path_join(
				"desktop_bridge/runtime/node.exe",
			),
		)
	else:
		candidates.append(executable_directory.path_join("node/node"))
	for candidate: String in candidates:
		if FileAccess.file_exists(candidate):
			return candidate
	return "node"
