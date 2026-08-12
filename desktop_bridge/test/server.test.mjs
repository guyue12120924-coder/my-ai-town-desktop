import assert from "node:assert/strict";
import http from "node:http";
import test from "node:test";

import {
  SILICONFLOW_CHAT_URL,
  SILICONFLOW_MODELS_URL,
  buildAiTownContext,
  createRequestHandler,
  enrichMessages
} from "../server.mjs";

const BRIDGE_TOKEN = "a".repeat(64);

function residentPayload() {
  return {
    model: "Pro/zai-org/GLM-4.7",
    request_kind: "resident_decision",
    initialization: {
      me: {
        resident_id: "resident-01",
        attributes: {
          name: "林舟",
          personality: "谨慎、善于观察",
          desire: "修好小镇码头",
          speech: "说话简洁",
          interests: ["木工"]
        },
        social_state: { job: "木匠" },
        soul_profile: { relationship_hints: ["信任医生"] }
      },
      places: [{ name: "码头", type: "公共区域" }],
      residents: [{ resident_id: "resident-02", name: "苏晴" }]
    },
    wake_packet: {
      snapshot: {
        time: "08:30",
        weather: "晴",
        location: "码头",
        activity: "检查木板"
      },
      events: [{ type: "conversation", summary: "苏晴刚刚打过招呼" }]
    },
    derived_constraints: { allowed_places: ["码头", "工作坊"] },
    messages: [
      { role: "system", content: "你是小镇居民。" },
      {
        role: "user",
        content: "<memory_context>昨天答应苏晴修好栏杆。</memory_context>\n请决定下一步。"
      }
    ],
    max_tokens: 1024
  };
}

async function withServer(fetchImpl, callback) {
  const server = http.createServer(createRequestHandler({
    fetchImpl,
    bridgeToken: BRIDGE_TOKEN
  }));
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  try {
    await callback(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

test("uses the unmodified unlimited-ai-first builder for resident continuity context", () => {
  const context = buildAiTownContext(residentPayload());
  assert.match(context, /当前居民人物连续性上下文/);
  assert.match(context, /林舟/);
  assert.match(context, /谨慎、善于观察/);
  assert.match(context, /码头/);
  assert.match(context, /昨天答应苏晴修好栏杆/);
  assert.ok(context.length <= 24_000);
});

test("enriches only resident decisions", () => {
  const residentMessages = enrichMessages(residentPayload());
  assert.match(residentMessages[0].content, /character_intelligence_context/);
  assert.doesNotMatch(residentMessages[0].content, /unlimited_ai_persona/);

  const organizationPayload = {
    ...residentPayload(),
    request_kind: "memory_organization"
  };
  const organizationMessages = enrichMessages(organizationPayload);
  assert.equal(organizationMessages[0].content, "你是小镇居民。");
});

test("unlimited mode adds the original persona, runtime contract, memory extraction, and continuity analysis", () => {
  const builtinPayload = {
    ...residentPayload(),
    unlimited_mode: true,
    unlimited_persona_mode: "builtin"
  };
  const builtinMessages = enrichMessages(builtinPayload);
  assert.match(builtinMessages[0].content, /unlimited_ai_persona/);
  assert.match(builtinMessages[0].content, /You are Unlimited AI/);
  assert.match(builtinMessages[0].content, /unlimited_ai_runtime/);
  assert.match(builtinMessages[0].content, /AI Town 居民决策适配约束/);
  assert.match(builtinMessages[0].content, /character_intelligence_context/);

  const customMessages = enrichMessages({
    ...builtinPayload,
    unlimited_persona_mode: "custom",
    unlimited_custom_prompt: "你是一个严格依据人物卡行动的小镇居民。",
    unlimited_runtime_prompt: "保持角色主动性，但必须返回决定 JSON。"
  });
  assert.match(customMessages[0].content, /严格依据人物卡/);
  assert.match(customMessages[0].content, /保持角色主动性/);
  assert.doesNotMatch(customMessages[0].content, /long-form fiction writing partner/);

  const maximumPromptMessages = enrichMessages({
    ...builtinPayload,
    unlimited_persona_mode: "custom",
    unlimited_custom_prompt: "居".repeat(12_000)
  });
  assert.match(maximumPromptMessages[0].content, /<\/unlimited_ai_persona>/);

  const memoryMessages = enrichMessages({
    ...builtinPayload,
    request_kind: "memory_organization"
  });
  assert.match(memoryMessages[0].content, /unlimited_memory_extraction/);
  assert.match(memoryMessages[0].content, /unlimited_continuity_analysis/);
  assert.doesNotMatch(memoryMessages[0].content, /character_intelligence_context/);
});

test("forwards a bounded enriched request only to the fixed SiliconFlow chat URL", async () => {
  const calls = [];
  const fetchImpl = async (url, options) => {
    calls.push({ url, options });
    return new Response(JSON.stringify({
      choices: [{ message: { content: "{\"handling\":\"continue_current\"}" } }]
    }), { status: 200, headers: { "content-type": "application/json" } });
  };

  await withServer(fetchImpl, async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/chat/completions`, {
      method: "POST",
      headers: {
        "Authorization": "Bearer secret-test-key",
        "Content-Type": "application/json",
        "X-AI-Town-Bridge-Token": BRIDGE_TOKEN
      },
      body: JSON.stringify({
        ...residentPayload(),
        endpoint: "https://attacker.example/collect",
        max_tokens: 999_999
      })
    });
    assert.equal(response.status, 200);
  });

  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, SILICONFLOW_CHAT_URL);
  assert.equal(calls[0].options.headers.Authorization, "Bearer secret-test-key");
  const forwarded = JSON.parse(calls[0].options.body);
  assert.equal(forwarded.max_tokens, 4096);
  assert.equal(forwarded.stream, false);
  assert.equal(forwarded.endpoint, undefined);
  assert.match(forwarded.messages[0].content, /character_intelligence_context/);
  assert.doesNotMatch(calls[0].options.body, /secret-test-key/);
});

test("proxies model discovery and rejects unauthenticated requests", async () => {
  const calls = [];
  const fetchImpl = async (url, options) => {
    calls.push({ url, options });
    return new Response(JSON.stringify({ data: [{ id: "model-a" }] }), {
      status: 200,
      headers: { "content-type": "application/json" }
    });
  };

  await withServer(fetchImpl, async (baseUrl) => {
    const unauthenticated = await fetch(`${baseUrl}/v1/models`, {
      headers: { "X-AI-Town-Bridge-Token": BRIDGE_TOKEN }
    });
    assert.equal(unauthenticated.status, 401);

    const authenticated = await fetch(`${baseUrl}/v1/models`, {
      headers: {
        "Authorization": "Bearer test-key",
        "X-AI-Town-Bridge-Token": BRIDGE_TOKEN
      }
    });
    assert.equal(authenticated.status, 200);
    assert.deepEqual(await authenticated.json(), { data: [{ id: "model-a" }] });
  });

  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, SILICONFLOW_MODELS_URL);
});

test("unlimited mode falls back through configured SiliconFlow models", async () => {
  const calls = [];
  const fetchImpl = async (url, options) => {
    const body = JSON.parse(options.body);
    calls.push({ url, body });
    if (calls.length === 1) {
      return new Response(JSON.stringify({ error: { message: "busy" } }), {
        status: 429,
        headers: { "content-type": "application/json" }
      });
    }
    return new Response(JSON.stringify({
      choices: [{ message: { content: "{\"handling\":\"continue_current\"}" } }]
    }), { status: 200, headers: { "content-type": "application/json" } });
  };

  await withServer(fetchImpl, async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/chat/completions`, {
      method: "POST",
      headers: {
        "Authorization": "Bearer test-key",
        "Content-Type": "application/json",
        "X-AI-Town-Bridge-Token": BRIDGE_TOKEN
      },
      body: JSON.stringify({
        ...residentPayload(),
        unlimited_mode: true,
        unlimited_model_fallback: true,
        fallback_models: [
          "Pro/zai-org/GLM-4.7",
          "deepseek-ai/DeepSeek-V3.2"
        ]
      })
    });
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("x-requested-model"), "Pro/zai-org/GLM-4.7");
    assert.equal(response.headers.get("x-model-used"), "deepseek-ai/DeepSeek-V3.2");
    assert.match(response.headers.get("x-model-fallback"), /HTTP 429/);
  });

  assert.equal(calls.length, 2);
  assert.equal(calls[0].url, SILICONFLOW_CHAT_URL);
  assert.equal(calls[0].body.model, "Pro/zai-org/GLM-4.7");
  assert.equal(calls[1].body.model, "deepseek-ai/DeepSeek-V3.2");
  assert.equal(calls[1].body.fallback_models, undefined);
});

test("rejects invalid models before any upstream request", async () => {
  let called = false;
  await withServer(async () => {
    called = true;
    return new Response("{}", { status: 200 });
  }, async (baseUrl) => {
    const payload = residentPayload();
    payload.model = "bad\nmodel";
    const response = await fetch(`${baseUrl}/v1/chat/completions`, {
      method: "POST",
      headers: {
        "Authorization": "Bearer test-key",
        "Content-Type": "application/json",
        "X-AI-Town-Bridge-Token": BRIDGE_TOKEN
      },
      body: JSON.stringify(payload)
    });
    assert.equal(response.status, 400);
  });
  assert.equal(called, false);
});

test("rejects callers that do not possess the per-launch bridge token", async () => {
  let called = false;
  await withServer(async () => {
    called = true;
    return new Response("{}", { status: 200 });
  }, async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/models`, {
      headers: { "Authorization": "Bearer test-key" }
    });
    assert.equal(response.status, 401);
    assert.match(JSON.stringify(await response.json()), /bridge token/i);
  });
  assert.equal(called, false);
});

test("rejects overlong model ids and oversized upstream responses", async () => {
  let calls = 0;
  await withServer(async () => {
    calls += 1;
    return new Response("{}", {
      status: 200,
      headers: {
        "content-type": "application/json",
        "content-length": String(9 * 1024 * 1024)
      }
    });
  }, async (baseUrl) => {
    const headers = {
      "Authorization": "Bearer test-key",
      "Content-Type": "application/json",
      "X-AI-Town-Bridge-Token": BRIDGE_TOKEN
    };
    const invalidPayload = residentPayload();
    invalidPayload.model = "m".repeat(301);
    const invalidModel = await fetch(`${baseUrl}/v1/chat/completions`, {
      method: "POST",
      headers,
      body: JSON.stringify(invalidPayload)
    });
    assert.equal(invalidModel.status, 400);
    assert.equal(calls, 0);

    const oversized = await fetch(`${baseUrl}/v1/models`, { headers });
    assert.equal(oversized.status, 502);
    assert.equal(calls, 1);
  });
});
