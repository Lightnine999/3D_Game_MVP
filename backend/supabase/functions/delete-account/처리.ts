export type DeleteAccountDependencies = {
  authenticate(request: Request): Promise<string | null> | string | null;
  deleteUser(userId: string): Promise<void> | void;
};

function json(status: number, payload: Record<string, unknown>): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

export async function handleDeleteAccount(request: Request, dependencies: DeleteAccountDependencies): Promise<Response> {
  if (request.method !== "POST") return json(405, { error: "method_not_allowed" });
  try {
    const userId = await dependencies.authenticate(request);
    if (!userId) return json(401, { error: "unauthorized" });

    let body: unknown;
    try {
      body = await request.json();
    } catch {
      return json(400, { error: "invalid_json" });
    }
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      return json(400, { error: "invalid_json" });
    }
    if ((body as Record<string, unknown>).confirm !== true) {
      return json(400, { error: "confirmation_required" });
    }

    // Do not accept the account ID from JSON. The Auth Admin API deletes the verified JWT owner.
    await dependencies.deleteUser(userId);
    return json(200, { status: "deleted" });
  } catch {
    return json(500, { error: "internal_error" });
  }
}
