export type AdminView = "admin_members" | "admin_purchases" | "admin_support";
export type AdminDependencies = {
  authenticate(request: Request): Promise<string | null> | string | null;
  isAdmin(userId: string): Promise<boolean> | boolean;
  list(view: AdminView): Promise<unknown[]> | unknown[];
};

const VIEW_BY_SECTION = {
  members: "admin_members",
  purchases: "admin_purchases",
  support: "admin_support",
} as const;

function json(status: number, payload: Record<string, unknown>): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

export async function handleAdminOverview(request: Request, deps: AdminDependencies): Promise<Response> {
  if (request.method !== "POST") return json(405, { error: "method_not_allowed" });
  try {
    const userId = await deps.authenticate(request);
    if (!userId) return json(401, { error: "unauthorized" });
    if (!await deps.isAdmin(userId)) return json(403, { error: "forbidden" });

    let body: unknown;
    try {
      body = await request.json();
    } catch {
      return json(400, { error: "invalid_json" });
    }
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      return json(400, { error: "invalid_json" });
    }
    const section = (body as Record<string, unknown>).section;
    if (typeof section !== "string" || !(section in VIEW_BY_SECTION)) {
      return json(400, { error: "invalid_section" });
    }
    const view = VIEW_BY_SECTION[section as keyof typeof VIEW_BY_SECTION];
    const items = await deps.list(view);
    if (!Array.isArray(items)) return json(500, { error: "internal_error" });
    return json(200, { section, items });
  } catch {
    return json(500, { error: "internal_error" });
  }
}
