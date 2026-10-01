import { needsHuman, validateSupportRequest, type SupportRequest } from "../_shared/문의.ts";
import type { ModelAnswer } from "../_shared/모델.ts";

type SupportStatus = "ai_answered" | "needs_human";
export type ConversationTurn = { role: "user" | "assistant"; content: string };
export type SupportDependencies = {
  authenticate(request: Request): Promise<string | null> | string | null;
  canAnswer(): boolean;
  create(userId: string, input: SupportRequest, requestId: string): Promise<string> | string;
  append?(userId: string, threadId: string, message: string, requestId: string): Promise<string | null> | string | null;
  history?(userId: string, threadId: string, requestId: string): Promise<ConversationTurn[]> | ConversationTurn[];
  release?(userId: string, threadId: string, requestId: string): Promise<void> | void;
  answer(message: string, history?: ConversationTurn[]): Promise<ModelAnswer>;
  finish(userId: string, threadId: string, status: SupportStatus, reply: string, requestId: string): Promise<void> | void;
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

    const requestId = crypto.randomUUID();
    const threadId = input.threadId
      ? await deps.append?.(userId, input.threadId, input.message, requestId)
      : await deps.create(userId, input, requestId);
    if (!threadId) return json(input.threadId ? 404 : 500, { error: input.threadId ? "thread_not_found" : "internal_error" });
    try {
      let status: SupportStatus = "needs_human";
      let reply = "팀에 전달했어요";
      if (!routeToHuman) {
        try {
          const history = deps.history ? await deps.history(userId, threadId, requestId) : undefined;
          const answer = await deps.answer(input.message, history);
          if (answer.status === "ai_answered" && answer.reply.trim()) {
            status = "ai_answered";
            reply = answer.reply.trim().slice(0, 2000);
          }
        } catch (error) {
          if (error instanceof Error && error.message === "support_request_expired") throw error;
          // The question is already stored as needing human review; do not leak provider errors.
        }
      }
      await deps.finish(userId, threadId, status, reply, requestId);
      return json(status === "ai_answered" ? 200 : 202, { threadId, status, reply });
    } finally {
      // Token-conditional cleanup cannot release a newer request. DB lease recovers crashes/outages.
      try { await deps.release?.(userId, threadId, requestId); } catch { /* lease expires */ }
    }
  } catch (error) {
    if (error instanceof Error && ["thread_busy", "support_request_expired"].includes(error.message)) {
      return json(409, { error: error.message });
    }
    if (error instanceof Error && error.message === "daily_limit_reached") {
      return json(429, { error: "daily_limit_reached" });
    }
    return json(500, { error: "internal_error" });
  }
}
