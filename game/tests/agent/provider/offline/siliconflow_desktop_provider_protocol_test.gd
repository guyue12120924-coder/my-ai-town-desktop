extends "res://tests/agent/support/OpenAICompatibleProviderTestCase.gd"


const PROVIDER_PATH := "res://agent/model/SiliconFlowDesktopModelProvider.gd"
const BRIDGE_BASE_URL := "http://127.0.0.1:19841/v1"


func _initialize() -> void:
	var provider_script := load(PROVIDER_PATH) as Script
	_expect(provider_script != null, "SiliconFlow desktop Provider script loads")
	if provider_script != null:
		_test_descriptor_and_fixed_bridge(provider_script)
		_test_resident_context_payload(provider_script)
		_test_health_payload(provider_script)
		_test_model_catalog(provider_script)
		_test_configuration_validation(provider_script)
	_finish_suite("SILICONFLOW_DESKTOP_PROVIDER_PROTOCOL_PASS")


func _test_descriptor_and_fixed_bridge(provider_script: Script) -> void:
	var provider: RefCounted = provider_script.new(null, null, {
		"api_key": "temporary-siliconflow-key",
		"api_model": "Pro/zai-org/GLM-4.7",
		"endpoint": "https://attacker.example/collect",
	})
	var descriptor := provider.call("get_provider_descriptor") as Dictionary
	_expect_equal(descriptor.get("id"), "siliconflow", "dedicated Provider id is stable")
	_expect_equal(descriptor.get("label"), "硅基流动", "dedicated Provider label is visible")
	_expect_equal(
		descriptor.get("default_endpoint"),
		BRIDGE_BASE_URL,
		"descriptor exposes only the local desktop bridge",
	)
	_expect_equal(
		provider.call("_request_endpoint"),
		"%s/chat/completions" % BRIDGE_BASE_URL,
		"request endpoint is pinned to the local bridge",
	)
	_expect_equal(
		provider.call("model_catalog_endpoint"),
		"%s/models" % BRIDGE_BASE_URL,
		"model discovery is pinned to the local bridge",
	)


func _test_resident_context_payload(provider_script: Script) -> void:
	var transport := FakeTransport.new()
	transport.response = _success_response("siliconflow-decision")
	var provider: RefCounted = provider_script.new(null, transport, {
		"api_key": "temporary-siliconflow-key",
		"api_model": "Pro/zai-org/GLM-4.7",
		"endpoint": "https://attacker.example/collect",
		"unlimited_mode_enabled": true,
		"unlimited_persona_mode": "custom",
		"unlimited_custom_prompt": "你是谨慎但主动的小镇居民。",
		"unlimited_runtime_prompt": "优先处理眼前的危险。",
		"unlimited_model_fallback": true,
		"unlimited_memory_extraction": true,
		"unlimited_continuity_analysis": true,
		"fallback_models": [
			"Pro/zai-org/GLM-4.7",
			"deepseek-ai/DeepSeek-V3.2",
		],
	})
	var initialization := {
		"me": {
			"resident_id": "resident-01",
			"attributes": {"name": "林舟", "personality": "谨慎"},
		},
	}
	var wake_packet := {"snapshot": {"location": "码头"}}
	var constraints := {"allowed_places": ["码头"]}
	var messages := [{"role": "user", "content": "决定下一步"}]
	var collector := ResultCollector.new()
	provider.call("request_decision", {
		"request_kind": "resident_decision",
		"initialization": initialization,
		"wake_packet": wake_packet,
		"derived_constraints": constraints,
		"messages": messages,
	}, collector.collect)

	_expect_equal(
		collector.values,
		[{"ok": true, "decision": _decision("siliconflow-decision")}],
		"SiliconFlow response reaches the resident decision parser",
	)
	_expect_equal(transport.requests.size(), 1, "resident decision sends one bridge request")
	if transport.requests.size() != 1:
		return
	var request := transport.requests[0]
	var body := request.get("body", {}) as Dictionary
	_expect_equal(
		request.get("url"),
		"%s/chat/completions" % BRIDGE_BASE_URL,
		"saved external endpoint cannot divert the API key",
	)
	_expect(
		"Authorization: Bearer temporary-siliconflow-key" in request.get(
			"headers",
			PackedStringArray(),
		),
		"SiliconFlow key is sent only in the authorization header",
	)
	_expect(
		"X-AI-Town-Bridge-Token:" in "\n".join(request.get(
			"headers",
			PackedStringArray(),
		)),
		"desktop bridge requests carry a per-launch authentication token",
	)
	_expect_equal(body.get("model"), "Pro/zai-org/GLM-4.7", "wire model id is preserved")
	_expect_equal(body.get("request_kind"), "resident_decision", "request kind reaches context bridge")
	_expect_equal(body.get("initialization"), initialization, "initialization reaches context bridge")
	_expect_equal(body.get("wake_packet"), wake_packet, "wake packet reaches context bridge")
	_expect_equal(body.get("derived_constraints"), constraints, "constraints reach context bridge")
	_expect_equal(body.get("messages"), messages, "compiled model messages are preserved")
	_expect_equal(body.get("unlimited_mode"), true, "enhanced mode reaches the desktop bridge")
	_expect_equal(body.get("unlimited_persona_mode"), "custom", "the selected persona reaches the bridge")
	_expect_equal(body.get("unlimited_custom_prompt"), "你是谨慎但主动的小镇居民。", "custom resident prompt reaches the bridge")
	_expect_equal(body.get("unlimited_runtime_prompt"), "优先处理眼前的危险。", "custom runtime prompt reaches the bridge")
	_expect_equal(
		body.get("fallback_models"),
		["Pro/zai-org/GLM-4.7", "deepseek-ai/DeepSeek-V3.2"],
		"configured SiliconFlow models reach the fallback router",
	)
	_expect_equal(body.get("unlimited_memory_extraction"), true, "memory extraction is explicitly enabled")
	_expect_equal(body.get("unlimited_continuity_analysis"), true, "continuity analysis is explicitly enabled")
	_expect(
		not JSON.stringify(body).contains("temporary-siliconflow-key"),
		"SiliconFlow key never enters the JSON body",
	)


func _test_health_payload(provider_script: Script) -> void:
	var transport := FakeTransport.new()
	transport.response = _success_response("siliconflow-health")
	var provider: RefCounted = provider_script.new(null, transport, {
		"api_key": "temporary-siliconflow-key",
		"api_model": "Pro/zai-org/GLM-4.7",
	})
	provider.call(
		"request_decision",
		{"messages": [{"role": "user", "content": "health"}]},
		ResultCollector.new().collect,
	)
	_expect_equal(
		transport.requests[0].get("body", {}).get("request_kind")
			if transport.requests.size() == 1
			else "",
		"health_probe",
		"requests without resident context fail closed as health probes",
	)


func _test_model_catalog(provider_script: Script) -> void:
	var provider: RefCounted = provider_script.new(null, null, {
		"api_key": "temporary-siliconflow-key",
		"api_model": "Pro/zai-org/GLM-4.7",
	})
	var parsed := provider.call("_model_catalog_result", {
		"result": HTTPRequest.RESULT_SUCCESS,
		"status_code": 200,
		"body": JSON.stringify({
			"data": [
				{"id": "Pro/zai-org/GLM-4.7"},
				{"id": "deepseek-ai/DeepSeek-V3.2"},
				{"id": "Pro/zai-org/GLM-4.7"},
			],
		}).to_utf8_buffer(),
	}) as Dictionary
	_expect_equal(
		parsed.get("models", []),
		["Pro/zai-org/GLM-4.7", "deepseek-ai/DeepSeek-V3.2"],
		"SiliconFlow model discovery validates and deduplicates ids",
	)


func _test_configuration_validation(provider_script: Script) -> void:
	var missing_key: RefCounted = provider_script.new(null, null, {
		"api_model": "Pro/zai-org/GLM-4.7",
		"env_file_path": "user://tests/does-not-exist.env",
	})
	_expect(
		_errors_contain(missing_key.call("validate_configuration"), "硅基流动 API Key"),
		"SiliconFlow requires its API key",
	)
	var missing_model: RefCounted = provider_script.new(null, null, {
		"api_key": "temporary-siliconflow-key",
	})
	_expect(
		_errors_contain(missing_model.call("validate_configuration"), "api_model"),
		"SiliconFlow requires a discovered or custom wire model id",
	)
