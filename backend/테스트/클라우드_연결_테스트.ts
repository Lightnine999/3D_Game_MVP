import assert from "node:assert/strict";

const moduleUrl = new URL("../supabase/functions/_shared/클라우드_연결.ts", import.meta.url).href;
const config = { url: "https://project.invalid", publicKey: "public-dummy", serviceKey: "server-dummy" };

Deno.test("사용자 검증에는 공개 키, DB RPC에는 서버 키만 사용한다", async () => {
  const { createCloudServices } = await import(moduleUrl);
  const calls: string[] = [];
  const services = createCloudServices(config, (_url: string, key: string) => ({
    auth: { getUser: (token: string) => {
      calls.push(`${key}:auth:${token}`);
      return Promise.resolve({ data: { user: { id: "user-a", is_anonymous: true } }, error: null });
    } },
    rpc: (name: string, args: unknown) => {
      calls.push(`${key}:rpc:${name}:${JSON.stringify(args)}`);
      return Promise.resolve({ data: 1, error: null });
    },
  }));
  const request = new Request("https://example.invalid", { headers: { authorization: "Bearer session" } });
  assert.deepEqual(await services.authenticate(request), { userId: "user-a", isAnonymous: true });
  assert.equal(await services.rpc("sync_submit", { p_user_id: "user-a" }), 1);
  assert.deepEqual(calls, ["public-dummy:auth:session", 'server-dummy:rpc:sync_submit:{"p_user_id":"user-a"}']);
});

Deno.test("DB 오류는 민감한 제공자 원문 없이 거부한다", async () => {
  const { createCloudServices } = await import(moduleUrl);
  const services = createCloudServices(config, () => ({
    auth: { getUser: () => Promise.resolve({ data: { user: null }, error: null }) },
    rpc: () => Promise.resolve({ data: null, error: new Error("provider-secret-text") }),
  }));
  await assert.rejects(() => services.rpc("sync_submit", {}), /^Error: db_failed$/);
});
