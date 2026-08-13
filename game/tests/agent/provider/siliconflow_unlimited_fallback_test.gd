extends SceneTree


const SiliconFlowProviderScript := preload(
	"res://agent/model/SiliconFlowDesktopModelProvider.gd"
)

var _failed := 0


func _initialize() -> void:
	var provider: RefCounted = SiliconFlowProviderScript.new(
		null,
		null,
		{
			"model": "model-a",
			"api_models": ["model-a", "model-b", "model-c"],
			"unlimited_mode_enabled": true,
			"unlimited_model_fallback": true,
		},
	)
	var body := provider.call("_build_request_body", {
		"request_kind": "resident_decision",
		"messages": [
			{"role": "system", "content": "SYSTEM"},
			{"role": "user", "content": "CONTEXT"},
		],
		"initialization": {},
		"wake_packet": {},
		"derived_constraints": {},
	}) as Dictionary

	_expect(bool(body.get("unlimited_mode", false)), "Unlimited 模式标记进入桥接请求")
	_expect(
		body.get("fallback_models", []) == ["model-a", "model-b", "model-c"],
		"未单独配置 fallback_models 时使用已添加的硅基流动模型列表",
	)

	var explicit_provider: RefCounted = SiliconFlowProviderScript.new(
		null,
		null,
		{
			"model": "model-a",
			"api_models": ["model-a", "model-b", "model-c"],
			"fallback_models": ["model-c"],
			"unlimited_mode_enabled": true,
			"unlimited_model_fallback": true,
		},
	)
	var explicit_body := explicit_provider.call("_build_request_body", {
		"request_kind": "resident_decision",
		"messages": [{"role": "system", "content": "SYSTEM"}],
	}) as Dictionary
	_expect(
		explicit_body.get("fallback_models", []) == ["model-c"],
		"显式 fallback_models 仍优先于默认模型列表",
	)

	if _failed == 0:
		print("SILICONFLOW_UNLIMITED_FALLBACK_PASS")
		quit(0)
	else:
		printerr("SILICONFLOW_UNLIMITED_FALLBACK_FAIL count=%d" % _failed)
		quit(1)


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failed += 1
	printerr("[FAIL] %s" % label)
