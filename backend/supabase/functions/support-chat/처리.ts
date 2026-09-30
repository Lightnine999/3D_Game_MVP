import { needsHuman, validateSupportRequest, type SupportRequest } from "../_shared/문의.ts";
import type { ModelAnswer } from "../_shared/모델.ts";

type SupportStatus = "ai_answered" | "needs_human";
export type SupportDependencies = {
  authenticate(request: Request): Promise<string | null> | string | null;
  canAnswer(): boolean;
  create(userId: string, input: SupportRequest): Promise<string> | string;
  answer(message: string): Promise<ModelAnswer>;
  finish(userId: string, threadId: string, status: SupportStatus, reply: string): Promise<void> | void;
};

function json(status: number, payload: Record<string, unknown>): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

export async function handleSupport(request: Request, deps: SupportDependencies): Promise<Response> {
  if (request.method !== "POST") return json(405, { error: "method_not_allowed" });
  try {
    const userId = await deps.authenticate(request);
    if (!userId) return json(401, { error: "unauthorized" });
    let input: SupportRequest;
    try {
      input = validateSupportRequest(await request.json());
    } catch {
      return json(400, { error: "invalid_support_request" });
    }
    const routeToHuman = needsHuman(input.kind, input.message);
    if (!routeToHuman && !deps.canAnswer()) return json(503, { error: "chat_key_missing" });

    const threadId = await deps.create(userId, input);
    if (!threadId) return json(500, { error: "internal_error" });
    let status: SupportStatus = "needs_human";
    let reply = "팀에 전달했어요";
    if (!routeToHuman) {
      try {
        const answer = await deps.answer(input.message);
        if (answer.status === "ai_answered" && answer.reply.trim()) {
          status = "ai_answered";
          reply = answer.reply.trim().slice(0, 2000);
        }
      } catch {
        // The question is already stored as needing human review; do not leak provider errors.
      }
    }
    await deps.finish(userId, threadId, status, reply);
    return json(status === "ai_answered" ? 200 : 202, { threadId, status, reply });
  } catch (error) {
    if (error instanceof Error && error.message === "daily_limit_reached") {
      return json(429, { error: "daily_limit_reached" });
    }
    return json(500, { error: "internal_error" });
  }
}
