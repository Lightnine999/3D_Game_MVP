import { GAME_GUIDE } from "./게임_안내_테스트.ts";

type FetchLike = (url: string, init: RequestInit) => Promise<Response>;
export type ModelAnswer = { status: "ai_answered" | "needs_human"; reply: string };

export async function askModel(
  apiKey: string,
  model: string,
  message: string,
  fetcher: FetchLike = fetch,
): Promise<ModelAnswer> {
  if (!apiKey || !model) throw new Error("chat_key_missing");
  let response: Response;
  try {
    response = await fetcher("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model, instructions: GAME_GUIDE, input: message, max_output_tokens: 400, store: false,
        text: { format: {
          type: "json_schema", name: "support_answer", strict: true,
          schema: {
            type: "object", additionalProperties: false,
            properties: {
              status: { type: "string", enum: ["ai_answered", "needs_human"] },
              reply: { type: "string" },
            },
            required: ["status", "reply"],
          },
        } },
      }),
    });
  } catch {
    throw new Error("model_request_failed");
  }
  if (!response.ok) throw new Error("model_request_failed");
  let value: unknown;
  try {
    value = await response.json();
  } catch {
    throw new Error("model_request_failed");
  }
  if (!value || typeof value !== "object") throw new Error("empty_model_reply");
  const result = value as Record<string, unknown>;
  if (result.status !== undefined && result.status !== "completed") throw new Error("model_request_failed");
  const output = Array.isArray(result.output) ? result.output : [];
  const parts: string[] = [];
  for (const item of output) {
    if (!item || typeof item !== "object") continue;
    const content = (item as Record<string, unknown>).content;
    if (!Array.isArray(content)) continue;
    for (const part of content) {
      if (part && typeof part === "object" && (part as Record<string, unknown>).type === "output_text" &&
          typeof (part as Record<string, unknown>).text === "string") {
        parts.push((part as { text: string }).text);
      }
    }
  }
  const text = parts.join("\n").trim();
  if (!text) throw new Error("empty_model_reply");
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new Error("invalid_model_reply");
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("invalid_model_reply");
  const answer = parsed as Record<string, unknown>;
  const reply = typeof answer.reply === "string" ? answer.reply.trim() : "";
  if ((answer.status !== "ai_answered" && answer.status !== "needs_human") ||
      !reply || reply.length > 2000 || Object.keys(answer).length !== 2) {
    throw new Error("invalid_model_reply");
  }
  return { status: answer.status, reply };
}
