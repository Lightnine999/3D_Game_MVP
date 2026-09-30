export type AdminReplyDependencies = {
  authenticate(request: Request): Promise<string | null> | string | null;
  isAdmin(userId: string): Promise<boolean> | boolean;
  reply(adminId: string, threadId: string, message: string, status: "in_progress" | "closed"): Promise<void> | void;
};

function json(status: number, payload: Record<string, unknown>): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

export async function handleAdminReply(request: Request, deps: AdminReplyDependencies): Promise<Response> {
  if (request.method !== "POST") return json(405, { error: "method_not_allowed" });
  try {
    const adminId = await deps.authenticate(request);
    if (!adminId) return json(401, { error: "unauthorized" });
    if (!await deps.isAdmin(adminId)) return json(403, { error: "forbidden" });

    let body: unknown;
    try {
      body = await request.json();
    } catch {
      return json(400, { error: "invalid_json" });
    }
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      return json(400, { error: "invalid_json" });
    }
    const input = body as Record<string, unknown>;
    const message = typeof input.reply === "string" ? input.reply.trim() : "";
    if (typeof input.threadId !== "string" || !input.threadId ||
        !message || message.length > 2000 ||
        (input.status !== "in_progress" && input.status !== "closed")) {
      return json(400, { error: "invalid_admin_reply" });
    }
    await deps.reply(adminId, input.threadId, message, input.status);
    return json(200, { threadId: input.threadId, status: input.status });
  } catch {
    return json(500, { error: "internal_error" });
  }
}
