import { validateEvents, type ProgressEvent } from "../_shared/동기화.ts";

export type SyncDependencies = {
  authenticate(request: Request): Promise<string | null> | string | null;
  submit(userId: string, events: ProgressEvent[]): Promise<number> | number;
};

function json(status: number, payload: Record<string, unknown>): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

export async function handleSync(request: Request, dependencies: SyncDependencies): Promise<Response> {
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

    let events: ProgressEvent[];
    try {
      events = validateEvents((body as Record<string, unknown>).events);
    } catch (error) {
      const code = error instanceof Error ? error.message : "invalid_event";
      return json(400, { error: code });
    }

    const inserted = await dependencies.submit(userId, events);
    if (!Number.isSafeInteger(inserted) || inserted < 0 || inserted > events.length) {
      return json(500, { error: "internal_error" });
    }
    return json(200, { received: events.length, inserted });
  } catch {
    // Provider errors can contain request data or credentials. Never return them to a client.
    return json(500, { error: "internal_error" });
  }
}
