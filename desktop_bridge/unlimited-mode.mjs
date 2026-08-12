import { getBuiltinPrompt } from "../vendor/unlimited-ai-first/src/prompts.js";


export const ORIGINAL_MODEL_RUNTIME_INJECTION = `
运行约束（由 Worker 注入）：
- 用户使用中文时默认使用自然、流畅的中文回复；用户明确指定其他语言时服从用户要求。
- 小说创作、续写、润色、改写任务直接输出可使用的正文，不解释“我将如何写”，除非用户明确要求分析。
- 不输出内部思维链、推理草稿、reasoning trace、<think> 标签或隐藏分析过程，只返回最终可用内容。
- 系统提供的当前正文、当前章节计划、人物状态、人物关系、世界规则、上一章摘要、未解决伏笔与连续性信息属于事实约束。
- 当不同背景信息出现冲突时，优先采用更近期、更具体、更接近当前章节的信息，不要用旧设定覆盖当前事实。
- 除非用户明确要求修改设定，不擅自改变已经确定的人名、身份、关系、伤势、位置、时间、知识状态、重要物品和世界规则。
- 长篇续写保持视角、时态、人物口吻、叙事节奏与前文事实一致，避免重复前文、机械总结和无依据新增设定。
- 用户要求大纲、分析、检查或建议时，再按对应任务输出结构化结果；不要把小说正文任务写成教程或说明。
`.trim();

export const AI_TOWN_DECISION_RUNTIME = `
AI Town 居民决策适配约束：
- 当前任务是模拟小镇居民下一步决定，不是续写小说正文。
- 必须服从现有 AI Town system message 中的动作合同、世界事实和 JSON schema。
- 只返回一个可被游戏解析的 JSON 对象；不要 Markdown、代码围栏、解释或正文。
- 不得虚构地图上不存在的地点、动作、人物、物品或已经完成的事件。
- 人物自由度只能在游戏明确允许的候选动作与事实范围内发挥。
`.trim();

export const AI_TOWN_MEMORY_EXTRACTION_RUNTIME = `
Unlimited AI 记忆提取适配：
- 继续使用当前 AI Town 记忆 schema，不要改成小说工作台的 items schema。
- 只保留材料中真实出现且会影响未来行为的事件、人物变化、关系变化、秘密、物品、地点、规则、冲突和未完成目标。
- 忽略一次性动作、普通环境描写和没有后续价值的琐碎信息。
- 不推测、不补写；新的完整记忆必须与旧记忆及已确认世界事实保持连续。
`.trim();

export const AI_TOWN_CONTINUITY_ANALYSIS_RUNTIME = `
Unlimited AI 连续性分析适配：
- 在当前 AI Town 记忆 schema 内检查人物位置、身体状况、情绪、目标、知识状态、关系立场、持续事件和未完成事项。
- 更近期、更具体、由世界运行结果确认的事实优先；不得用旧状态覆盖新事实。
- 没有证据的变化不要写入；已经解决的事项不得继续当作未解决事项。
- 输出仍须严格服从当前请求原有的 JSON 合同。
`.trim();

const SAFE_REQUEST_KINDS = new Set([
  "resident_decision",
  "memory_organization",
  "avatar_memory_organization"
]);


function cleanText(value, limit = 12_000) {
  const text = String(value ?? "").trim();
  if (!text) return "";
  return text.length > limit ? text.slice(0, limit) : text;
}


function cleanModel(value) {
  return String(value ?? "").trim();
}


function appendSystemBlocks(messages, blocks) {
  const usefulBlocks = blocks.map((block) => cleanText(block, 16_000)).filter(Boolean);
  if (!usefulBlocks.length) return messages;
  const prepared = messages.map((message) => ({ ...message }));
  const addition = usefulBlocks.join("\n\n");
  const systemIndex = prepared.findIndex(
    (message) => message?.role === "system" && typeof message?.content === "string"
  );
  if (systemIndex >= 0) {
    prepared[systemIndex] = {
      ...prepared[systemIndex],
      content: `${prepared[systemIndex].content}\n\n${addition}`
    };
  } else {
    prepared.unshift({ role: "system", content: addition });
  }
  return prepared;
}


export function unlimitedModeEnabled(payload) {
  return payload?.unlimited_mode === true;
}


export function enrichUnlimitedMessages(payload, messages) {
  if (!unlimitedModeEnabled(payload)) return messages;
  const requestKind = String(payload?.request_kind ?? "");
  if (!SAFE_REQUEST_KINDS.has(requestKind)) return messages;

  if (requestKind === "resident_decision") {
    const personaMode = payload?.unlimited_persona_mode === "custom"
      ? "custom"
      : "builtin";
    const personaPrompt = personaMode === "custom"
      ? cleanText(payload?.unlimited_custom_prompt)
      : getBuiltinPrompt("creative-primary");
    const runtimePrompt = cleanText(payload?.unlimited_runtime_prompt)
      || ORIGINAL_MODEL_RUNTIME_INJECTION;
    return appendSystemBlocks(messages, [
      `<unlimited_ai_persona>\n${personaPrompt}\n</unlimited_ai_persona>`,
      `<unlimited_ai_runtime>\n${runtimePrompt}\n</unlimited_ai_runtime>`,
      `<ai_town_decision_contract>\n${AI_TOWN_DECISION_RUNTIME}\n</ai_town_decision_contract>`
    ]);
  }

  const blocks = [];
  if (payload?.unlimited_memory_extraction !== false) {
    blocks.push(
      `<unlimited_memory_extraction>\n${AI_TOWN_MEMORY_EXTRACTION_RUNTIME}\n</unlimited_memory_extraction>`
    );
  }
  if (payload?.unlimited_continuity_analysis !== false) {
    blocks.push(
      `<unlimited_continuity_analysis>\n${AI_TOWN_CONTINUITY_ANALYSIS_RUNTIME}\n</unlimited_continuity_analysis>`
    );
  }
  return appendSystemBlocks(messages, blocks);
}


export function fallbackModels(payload) {
  const requested = cleanModel(payload?.model);
  if (!requested) return [];
  const result = [requested];
  if (!unlimitedModeEnabled(payload) || payload?.unlimited_model_fallback === false) {
    return result;
  }
  const configured = Array.isArray(payload?.fallback_models)
    ? payload.fallback_models
    : [];
  for (const value of configured) {
    const model = cleanModel(value);
    if (!model || result.includes(model)) continue;
    result.push(model);
    if (result.length >= 10) break;
  }
  return result;
}


export function shouldFallback(status) {
  return status === 400
    || status === 404
    || status === 408
    || status === 409
    || status === 410
    || status === 429
    || status >= 500;
}
