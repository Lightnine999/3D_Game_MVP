import assert from "node:assert/strict";

const moduleUrl = new URL("../supabase/functions/ensure-profile/처리.ts", import.meta.url).href;

function post(body: unknown): Request {
  return new Request("https://example.invalid/functions/v1/ensure-profile", {
    method: "POST",
    headers: { "content-type": "application/json", authorization: "Bearer test-session" },
    body: JSON.stringify(body),
  });
}

Deno.test("프로필은 JWT 사용자와 Auth 게스트 여부만으로 생성한다", async () => {
  const { handleEnsureProfile } = await import(moduleUrl);
  const calls: unknown[] = [];
  const response = await handleEnsureProfile(post({ user_id: "other", role: "admin", is_guest: false }), {
    authenticate: () => ({ userId: "user-a", isAnonymous: true }),
    ensure: (userId: string, isGuest: boolean) => {
      calls.push({ userId, isGuest });
      return { user_id: userId, nickname: "", is_guest: isGuest, role: "user" };
    },
  });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { profile: { user_id: "user-a", nickname: "", is_guest: true, role: "user" } });
  assert.deepEqual(calls, [{ userId: "user-a", isGuest: true }]);
});

Deno.test("영구 계정 재호출에도 DB의 관리자 역할은 보존한다", async () => {
  const { handleEnsureProfile } = await import(moduleUrl);
  const response = await handleEnsureProfile(post({}), {
    authenticate: () => ({ userId: "user-a", isAnonymous: false }),
    ensure: (_userId: string, isGuest: boolean) => ({ user_id: "user-a", nickname: "owner", is_guest: isGuest, role: "admin" }),
  });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { profile: { user_id: "user-a", nickname: "owner", is_guest: false, role: "admin" } });
});

Deno.test("무인증·잘못된 메서드·DB 장애는 쓰기를 막고 세부 오류를 숨긴다", async () => {
  const { handleEnsureProfile } = await import(moduleUrl);
  let writes = 0;
  const denied = await handleEnsureProfile(post({}), {
    authenticate: () => null,
    ensure: () => { writes++; throw new Error("must not run"); },
  });
  assert.equal(denied.status, 401);
  assert.equal(writes, 0);

  const wrongMethod = await handleEnsureProfile(new Request("https://example.invalid/functions/v1/ensure-profile"), {
    authenticate: () => ({ userId: "user-a", isAnonymous: true }),
    ensure: () => { writes++; throw new Error("must not run"); },
  });
  assert.equal(wrongMethod.status, 405);
  assert.equal(writes, 0);

  const failed = await handleEnsureProfile(post({}), {
    authenticate: () => ({ userId: "user-a", isAnonymous: true }),
    ensure: () => { throw new Error("db-credential-not-for-client"); },
  });
  assert.equal(failed.status, 500);
  assert.deepEqual(await failed.json(), { error: "internal_error" });
});
