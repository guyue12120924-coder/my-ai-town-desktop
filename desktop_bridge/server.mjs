import http from "node:http";
import { timingSafeEqual } from "node:crypto";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { buildCreativeContextMessage } from "../vendor/unlimited-ai-first/src/context.js";

export const BRIDGE_HOST = "127.0.0.1";
export const DEFAULT_BRIDGE_PORT = 19841;
export const SILICONFLOW_CHAT_URL = "https://api.siliconflow.cn/v1/chat/completions";
export const SILICONFLOW_MODELS_URL = "https://api.siliconflow.cn/v1/models";
export const UNLIMITED_AI_COMMIT = "64409d7ad930e7ff5948f2c15764c440741d01ae";

const MAX_BODY_BYTES = 2 * 1024 * 1024;
const MAX_UPSTREAM_RESPONSE_BYTES = 8 * 1024 * 1024;
const UPSTREAM_TIMEOUT_MS = 120_000;
const ALLOWED_ROLES = new Set(["system", "user", "assistant", "tool"]);

function cleanText(value, limit = 6000) {
  const normalized = String(value ?? "").trim();
  if (!normalized) return "";
  return normalized.length > limit ? normalized.slice(0, limit) : normalized;
}

function objectValue(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function arrayValue(value) {
  return Array.isArray(value) ? value : [];
}

function extractTaggedSection(messages, tag) {
  const source = arrayValue(messages)
    .map((message) => typeof message?.content === "string" ? message.content : "")
    .join("\n");
  const open = `<${tag}>`;
  const close = `</${tag}>`;
  const start = source.indexOf(open);
  const end = source.indexOf(close, start + open.length);
  if (start < 0 || end <= start) return "";
  return cleanText(source.slice(start + open.length, end), 6500);
}

function renderCurrentState(wakePacket) {
  const wake = objectValue(wakePacket);
  const snapshot = objectValue(wake.snapshot);
  return cleanText(JSON.stringify({
    time: snapshot.time ?? wake.time ?? "",
    weather: snapshot.weather ?? "",
    weather_context: snapshot.weather_context ?? "",
    location: snapshot.location ?? snapshot.place ?? "",
    activity: snapshot.activity ?? snapshot.current_activity ?? "",
    body_state: snapshot.body_state ?? snapshot.body ?? {},
    conditions: snapshot.conditions ?? snapshot.active_needs ?? [],
    work_tasks: snapshot.work_tasks ?? [],
    social_matters: snapshot.social_matters ?? [],
    nearby_residents: snapshot.nearby_residents ?? snapshot.nearby ?? [],
    conflicts: snapshot.conflicts ?? snapshot.conflict ?? [],
    announcements: snapshot.announcements ?? [],
    recent_events: wake.events ?? [],
    action_results: wake.action_results ?? []
  }, null, 2), 5000);
}

export function buildAiTownContext(payload) {
  const initialization = objectValue(payload.initialization);
  const me = objectValue(initialization.me);
  const attributes = objectValue(me.attributes);
  const socialState = objectValue(me.social_state);
  const soulProfile = objectValue(me.soul_profile);
  const wakePacket = objectValue(payload.wake_packet);
  const derivedConstraints = objectValue(payload.derived_constraints);
  if (!Object.keys(initialization).length || !Object.keys(wakePacket).length) return "";

  const name = cleanText(attributes.name || me.name || me.resident_id || "居民", 120);
  const specialIdentities = arrayValue(soulProfile.special_identities)
    .map((item) => typeof item === "string" ? item : item?.label)
    .filter(Boolean);
  const relationshipHints = arrayValue(soulProfile.relationship_hints);
  const interests = [
    ...arrayValue(attributes.interests),
    ...arrayValue(attributes.customInterests)
  ].filter(Boolean);
  const currentState = renderCurrentState(wakePacket);
  const residentMemory = extractTaggedSection(payload.messages, "memory_context");

  const creativeContext = {
    project: {
      name: "AI Town",
      description: "LLM 驱动居民生活的持续世界模拟。居民必须忠于自己的稳定人物设定，同时以 Godot 世界确认的事实为准。",
      worldOverview: cleanText(JSON.stringify({
        known_places: initialization.places ?? [],
        known_residents: initialization.residents ?? []
      }, null, 2), 5000),
      worldRules: cleanText(JSON.stringify(derivedConstraints, null, 2), 4200),
      relations: cleanText(JSON.stringify(relationshipHints, null, 2), 3200)
    },
    characters: [{
      name,
      role: cleanText(socialState.job, 300),
      personality: cleanText(attributes.personality, 1000),
      goal: cleanText(attributes.desire, 900),
      voice: cleanText(attributes.speech, 900),
      currentState,
      notes: cleanText(JSON.stringify({ interests, specialIdentities, soulProfile }, null, 2), 2200)
    }]
  };
  const memoryContext = residentMemory ? {
    items: [{
      type: "人物记忆",
      content: residentMemory,
      characters: [name],
      tags: ["AI Town", "居民记忆"],
      importance: 5
    }]
  } : { items: [] };
  const continuityContext = {
    characterStates: currentState ? [{ name, state: currentState }] : []
  };

  return buildCreativeContextMessage(
    creativeContext,
    memoryContext,
    continuityContext
  )
    .replace("# 当前小说创作上下文", "# 当前居民人物连续性上下文")
    .replace(
      "正式正文与已确认的连续性状态优先于宽泛总纲。",
      "已确认的世界事实与人物连续性状态优先于宽泛背景。"
    );
}

export function enrichMessages(payload) {
  const messages = arrayValue(payload.messages).map((message) => ({ ...message }));
  if (payload.request_kind !== "resident_decision") return messages;
  const context = buildAiTownContext(payload);
  if (!context) return messages;

  const block = `<character_intelligence_context>\n${context}\n</character_intelligence_context>`;
  const systemIndex = messages.findIndex(
    (message) => message?.role === "system" && typeof message?.content === "string"
  );
  if (systemIndex >= 0) {
    messages[systemIndex] = {
      ...messages[systemIndex],
      content: `${messages[systemIndex].content}\n\n${block}`
    };
  } else {
    messages.unshift({ role: "system", content: block });
  }
  return messages;
}

function jsonResponse(response, status, value) {
  const body = JSON.stringify(value);
  response.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "Content-Length": Buffer.byteLength(body)
  });
  response.end(body);
}

function bearerToken(request) {
  const authorization = String(request.headers.authorization ?? "");
  if (!authorization.startsWith("Bearer ")) return "";
  const token = authorization.slice(7).trim();
  if (!token || token.length > 2048 || /[\u0000-\u001f\u007f]/.test(token)) return "";
  return token;
}

function validBridgeToken(request, expectedToken) {
  if (!expectedToken) return false;
  const received = String(request.headers["x-ai-town-bridge-token"] ?? "");
  if (!received || received.length !== expectedToken.length) return false;
  return timingSafeEqual(Buffer.from(received), Buffer.from(expectedToken));
}

async function readJsonBody(request) {
  const declaredLength = Number(request.headers["content-length"] ?? 0);
  if (Number.isFinite(declaredLength) && declaredLength > MAX_BODY_BYTES) {
    throw Object.assign(new Error("request body is too large"), { status: 413 });
  }
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > MAX_BODY_BYTES) {
      throw Object.assign(new Error("request body is too large"), { status: 413 });
    }
    chunks.push(chunk);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    throw Object.assign(new Error("request body must be valid JSON"), { status: 400 });
  }
}

function validMessages(value) {
  if (!Array.isArray(value) || value.length < 1 || value.length > 10) return false;
  return value.every((message) => {
    if (!message || typeof message !== "object" || Array.isArray(message)) return false;
    if (!ALLOWED_ROLES.has(String(message.role ?? ""))) return false;
    return typeof message.content === "string" || Array.isArray(message.content);
  });
}

function normalizedChatBody(payload) {
  const rawModel = String(payload.model ?? "").trim();
  if (
    !rawModel
    || rawModel.length > 300
    || /[\u0000-\u001f\u007f]/.test(rawModel)
  ) {
    throw Object.assign(new Error("model must be a non-empty model id"), { status: 400 });
  }
  const messages = enrichMessages(payload);
  if (!validMessages(messages)) {
    throw Object.assign(new Error("messages must contain 1 to 10 valid messages"), { status: 400 });
  }
  const requestedMaxTokens = Number(payload.max_tokens);
  const maxTokens = Number.isFinite(requestedMaxTokens)
    ? Math.max(64, Math.min(4096, Math.trunc(requestedMaxTokens)))
    : 1024;
  return { model: rawModel, messages, stream: false, max_tokens: maxTokens };
}

async function readBoundedUpstreamBody(response) {
  const declaredLength = Number(response.headers.get("content-length") ?? 0);
  if (
    Number.isFinite(declaredLength)
    && declaredLength > MAX_UPSTREAM_RESPONSE_BYTES
  ) {
    await response.body?.cancel();
    throw new Error("SiliconFlow response exceeded the bridge limit");
  }
  if (!response.body) return Buffer.alloc(0);
  const chunks = [];
  let size = 0;
  for await (const chunk of response.body) {
    size += chunk.byteLength;
    if (size > MAX_UPSTREAM_RESPONSE_BYTES) {
      await response.body.cancel();
      throw new Error("SiliconFlow response exceeded the bridge limit");
    }
    chunks.push(Buffer.from(chunk));
  }
  return Buffer.concat(chunks, size);
}

async function upstreamRequest(url, apiKey, options, fetchImpl) {
  const response = await fetchImpl(url, {
    ...options,
    headers: {
      ...(options.headers ?? {}),
      "Accept": "application/json",
      "Authorization": `Bearer ${apiKey}`
    },
    signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS)
  });
  const body = await readBoundedUpstreamBody(response);
  return {
    status: response.status,
    contentType: response.headers.get("content-type") || "application/json; charset=utf-8",
    body
  };
}

function sendUpstream(response, upstream) {
  response.writeHead(upstream.status, {
    "Content-Type": upstream.contentType,
    "Cache-Control": "no-store",
    "Content-Length": upstream.body.length,
    "X-AI-Town-Context": "unlimited-ai-first/context.js",
    "X-Unlimited-AI-Commit": UNLIMITED_AI_COMMIT
  });
  response.end(upstream.body);
}

export function createRequestHandler({ fetchImpl = fetch, bridgeToken = "" } = {}) {
  return async function handleRequest(request, response) {
    try {
      const url = new URL(request.url ?? "/", `http://${BRIDGE_HOST}`);
      if (!validBridgeToken(request, bridgeToken)) {
        return jsonResponse(response, 401, { error: { message: "Invalid desktop bridge token" } });
      }
      if (request.method === "GET" && url.pathname === "/health") {
        return jsonResponse(response, 200, {
          ok: true,
          service: "ai-town-desktop-context-bridge",
          upstreamCommit: UNLIMITED_AI_COMMIT
        });
      }

      const apiKey = bearerToken(request);
      if (!apiKey) {
        return jsonResponse(response, 401, { error: { message: "Missing SiliconFlow API key" } });
      }

      if (request.method === "GET" && url.pathname === "/v1/models") {
        const upstream = await upstreamRequest(
          SILICONFLOW_MODELS_URL,
          apiKey,
          { method: "GET" },
          fetchImpl
        );
        return sendUpstream(response, upstream);
      }

      if (request.method === "POST" && url.pathname === "/v1/chat/completions") {
        const payload = await readJsonBody(request);
        const body = normalizedChatBody(payload);
        const upstream = await upstreamRequest(
          SILICONFLOW_CHAT_URL,
          apiKey,
          {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(body)
          },
          fetchImpl
        );
        return sendUpstream(response, upstream);
      }

      return jsonResponse(response, 404, { error: { message: "Not found" } });
    } catch (error) {
      const status = Number(error?.status) || (error?.name === "TimeoutError" ? 504 : 502);
      const publicMessage = status < 500 ? error.message : "SiliconFlow request failed";
      return jsonResponse(response, status, { error: { message: publicMessage } });
    }
  };
}

function argumentValue(name, fallback = "") {
  const index = process.argv.indexOf(name);
  return index >= 0 && index + 1 < process.argv.length ? process.argv[index + 1] : fallback;
}

export function startBridgeServer({
  port = DEFAULT_BRIDGE_PORT,
  parentPid = 0,
  bridgeToken = ""
} = {}) {
  if (!/^[0-9a-f]{64}$/.test(bridgeToken)) {
    throw new Error("A 256-bit desktop bridge token is required");
  }
  const server = http.createServer(createRequestHandler({ bridgeToken }));
  server.requestTimeout = 125_000;
  server.headersTimeout = 10_000;
  server.keepAliveTimeout = 5_000;
  server.listen(port, BRIDGE_HOST, () => {
    console.log(`AI Town desktop context bridge ready on ${BRIDGE_HOST}:${port}`);
  });

  if (parentPid > 0) {
    const parentTimer = setInterval(() => {
      try {
        process.kill(parentPid, 0);
      } catch {
        clearInterval(parentTimer);
        server.close(() => process.exit(0));
      }
    }, 3000);
    parentTimer.unref();
  }
  return server;
}

const entryUrl = process.argv[1] ? pathToFileURL(process.argv[1]).href : "";
if (import.meta.url === entryUrl) {
  const port = Number(argumentValue("--port", String(DEFAULT_BRIDGE_PORT)));
  const parentPid = Number(argumentValue("--parent-pid", "0"));
  const bridgeToken = argumentValue("--bridge-token", "");
  if (!Number.isInteger(port) || port < 1024 || port > 65535) {
    console.error("Invalid bridge port");
    process.exit(2);
  }
  if (!/^[0-9a-f]{64}$/.test(bridgeToken)) {
    console.error("Missing or invalid desktop bridge token");
    process.exit(2);
  }
  startBridgeServer({
    port,
    parentPid: Number.isInteger(parentPid) ? parentPid : 0,
    bridgeToken
  });
}
