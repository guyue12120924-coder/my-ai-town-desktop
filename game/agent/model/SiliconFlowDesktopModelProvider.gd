class_name SiliconFlowDesktopModelProvider
extends "res://agent/model/GenericOpenAICompatibleModelProvider.gd"


const BridgeHostScript := preload(
	"res://desktop/SiliconFlowDesktopBridge.gd"
)


func _init(
	request_host: Node = null,
	transport: Object = null,
	config: Dictionary = {},
) -> void:
	var resolved_config := config.duplicate(true)
	resolved_config["endpoint"] = BridgeHostScript.base_url()
	resolved_config["preset_default_endpoint"] = BridgeHostScript.base_url()
	resolved_config["preset_provider_id"] = "siliconflow"
	resolved_config["preset_provider_label"] = "硅基流动"
	resolved_config["preset_transport_label"] = (
		"硅基流动桌面上下文桥"
	)
	resolved_config["preset_api_key_environment"] = "SILICONFLOW_API_KEY"
	resolved_config["preset_api_key_required"] = true
	resolved_config["timeout_seconds"] = 125.0
	super(request_host, transport, resolved_config)


func get_provider_descriptor() -> Dictionary:
	var descriptor := super.get_provider_descriptor()
	descriptor["id"] = "siliconflow"
	descriptor["label"] = "硅基流动"
	descriptor["transport_label"] = "硅基流动桌面上下文桥"
	descriptor["auth_required"] = true
	descriptor["default_endpoint"] = BridgeHostScript.base_url()
	descriptor["custom_models"] = true
	descriptor["custom_group"] = true
	descriptor["model_catalog_supported"] = true
	descriptor["desktop_bridge_required"] = true
	return descriptor


func _provider_id() -> String:
	return "siliconflow"


func _provider_label() -> String:
	return "硅基流动"


func _transport_label() -> String:
	return "硅基流动桌面上下文桥"


func _default_endpoint() -> String:
	return BridgeHostScript.base_url()


func _default_model() -> String:
	return DEFAULT_MODEL


func _request_endpoint() -> String:
	return "%s/chat/completions" % BridgeHostScript.base_url()


func model_catalog_endpoint() -> String:
	return "%s/models" % BridgeHostScript.base_url()


func _api_key_environment_names() -> Array[String]:
	return ["SILICONFLOW_API_KEY"]


func _provider_request_headers() -> PackedStringArray:
	return BridgeHostScript.request_headers()


func _missing_api_key_message(include_hint: bool) -> String:
	var message := "缺少硅基流动 API Key"
	if include_hint:
		message += "；请在模型设置页保存 API Key"
	return message


func validate_configuration() -> Array[String]:
	var errors := super.validate_configuration()
	if OS.has_feature("web"):
		errors.append("硅基流动人物上下文桥仅支持桌面版")
	elif not BridgeHostScript.is_ready():
		errors.append("硅基流动桌面上下文桥尚未就绪，请稍后重试")
	return errors


func _build_request_body(model_request: Dictionary) -> Dictionary:
	var body := super._build_request_body(model_request)
	body["request_kind"] = String(
		model_request.get("request_kind", "health_probe"),
	)
	body["initialization"] = (
		model_request.get("initialization", {}) as Dictionary
	).duplicate(true)
	body["wake_packet"] = (
		model_request.get("wake_packet", {}) as Dictionary
	).duplicate(true)
	body["derived_constraints"] = (
		model_request.get("derived_constraints", {}) as Dictionary
	).duplicate(true)
	return body
