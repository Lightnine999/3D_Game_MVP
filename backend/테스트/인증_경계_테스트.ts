import assert from "node:assert/strict";

const moduleUrl = new URL("../supabase/functions/_shared/인증.ts", import.meta.url).href;

Deno.test("검증된 Bearer 토큰에서만 사용자 ID를 얻는다", async () => {
  const { verifiedUserId } = await import(moduleUrl);
  const tokens: string[] = [];
  const request = new Request("https://example.invalid", { headers: { authorization: "Bearer test-session" } });
  const userId = await verifiedUserId(request, (token: string) => {
    tokens.push(token);
    return Promise.resolve({ id: "user-a" });
  });
  assert.equal(userId, "user-a");
  assert.deepEqual(tokens, ["test-session"]);
});

Deno.test("토큰이 없거나 형식이 다르면 인증 조회조차 하지 않는다", async () => {
  const { verifiedUserId } = await import(moduleUrl);
  let calls = 0;
  const lookup = () => { calls++; return Promise.resolve({ id: "user-a" }); };
  assert.equal(await verifiedUserId(new Request("https://example.invalid"), lookup), null);
  assert.equal(await verifiedUserId(new Request("https://example.invalid", { headers: { authorization: "Basic wrong" } }), lookup), null);
  assert.equal(calls, 0);
});

Deno.test("인증 제공자의 거부·장애는 사용자 ID를 만들지 않는다", async () => {
  const { verifiedUserId } = await import(moduleUrl);
  const request = new Request("https://example.invalid", { headers: { authorization: "Bearer expired" } });
  assert.equal(await verifiedUserId(request, () => Promise.resolve(null)), null);
  assert.equal(await verifiedUserId(request, () => Promise.reject(new Error("provider-sensitive-detail"))), null);
});

Deno.test("게스트 여부도 클라이언트 JSON이 아니라 Auth 확인 결과에서 얻는다", async () => {
  const { verifiedAccount } = await import(moduleUrl);
  const request = new Request("https://example.invalid", { headers: { authorization: "Bearer guest-token" } });
  assert.deepEqual(await verifiedAccount(request, () => Promise.resolve({ id: "user-a", is_anonymous: true })), {
    userId: "user-a", isAnonymous: true,
  });
  assert.deepEqual(await verifiedAccount(request, () => Promise.resolve({ id: "user-a", is_anonymous: false })), {
    userId: "user-a", isAnonymous: false,
  });
  assert.equal(await verifiedAccount(new Request("https://example.invalid"), () => Promise.resolve({ id: "other" })), null);
});
