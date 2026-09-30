export type VerifiedAccount = { userId: string; isAnonymous: boolean };
export type AuthUser = { id: string; is_anonymous?: boolean };
export type UserLookup = (token: string) => Promise<AuthUser | null> | AuthUser | null;

export async function verifiedAccount(request: Request, lookup: UserLookup): Promise<VerifiedAccount | null> {
  const authorization = request.headers.get("authorization");
  const token = authorization?.match(/^Bearer\s+(\S+)$/i)?.[1];
  if (!token) return null;

  try {
    const user = await lookup(token);
    return typeof user?.id === "string" && user.id.length > 0
      ? { userId: user.id, isAnonymous: user.is_anonymous === true }
      : null;
  } catch {
    // A provider error cannot authenticate a caller, and must not leak into a response.
    return null;
  }
}

export async function verifiedUserId(request: Request, lookup: UserLookup): Promise<string | null> {
  return (await verifiedAccount(request, lookup))?.userId ?? null;
}
