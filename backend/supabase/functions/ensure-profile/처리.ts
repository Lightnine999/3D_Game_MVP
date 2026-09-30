export type VerifiedAccount = {
  userId: string;
  isAnonymous: boolean;
};

export type Profile = {
  user_id: string;
  nickname: string;
  is_guest: boolean;
  role: "user" | "admin";
};

export type ProfileDependencies = {
  authenticate(request: Request): Promise<VerifiedAccount | null> | VerifiedAccount | null;
  ensure(userId: string, isGuest: boolean): Promise<Profile> | Profile;
};

function json(status: number, payload: Record<string, unknown>): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

export async function handleEnsureProfile(request: Request, dependencies: ProfileDependencies): Promise<Response> {
  if (request.method !== "POST") return json(405, { error: "method_not_allowed" });
  try {
    const account = await dependencies.authenticate(request);
    if (!account) return json(401, { error: "unauthorized" });

    // Never accept user_id, role or is_guest from the client's JSON body.
    const profile = await dependencies.ensure(account.userId, account.isAnonymous);
    if (profile.user_id !== account.userId) return json(500, { error: "internal_error" });
    return json(200, { profile });
  } catch {
    return json(500, { error: "internal_error" });
  }
}
