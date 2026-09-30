import assert from "node:assert/strict";

const moduleUrl = new URL("../supabase/functions/sync-progress/처리.ts", import.meta.url).href;
const validEvents = [{ id: "evt_001", kind: "mission", payload: { stage_id: "field_01", mission_id: "M1" } }];

function post(body: unknown): Request {
  return new Request("https://example.invalid/functions/v1/sync-progress", {
    method: "POST",
    headers: { "content-type": "application/json", authorization: "Bearer test-session" },
    body: JSON.stringify(body),
  });
}

Deno.test("동기화는 JWT 사용자만 DB에 전달하고 클라이언트 user_id를 무시한다", async () => {
  const { handleSync } = await import(moduleUrl);
  const calls: unknown[] = [];
  const response = await handleSync(post({ user_id: "attacker", events: validEvents }), {
    authenticate: () => "user-a",
    submit: (userId: string, events: unknown[]) => {
      calls.push({ userId, events });
      return 1;
    },
  });

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { received: 1, inserted: 1 });
  assert.deepEqual(calls, [{ userId: "user-a", events: validEvents }]);
});

Deno.test("인증 없음·잘못된 종류·GET 요청은 DB 쓰기 전에 거부한다", async () => {
  const { handleSync } = await import(moduleUrl);
  let writes = 0;
  const denied = { authenticate: () => null, submit: () => { writes++; return 1; } };
  const unauthenticated = await handleSync(post({ events: validEvents }), denied);
  assert.equal(unauthenticated.status, 401);

  const authenticated = { authenticate: () => "user-a", submit: denied.submit };
  const invalid = await handleSync(post({ events: [{ id: "evt_2", kind: "purchase", payload: {} }] }), authenticated);
  assert.equal(invalid.status, 400);
  assert.deepEqual(await invalid.json(), { error: "invalid_event" });

  const wrongMethod = await handleSync(new Request("https://example.invalid/functions/v1/sync-progress"), authenticated);
  assert.equal(wrongMethod.status, 405);
  assert.equal(writes, 0);
});

Deno.test("중복 전송 0건은 성공이고 DB 오류 내용은 노출하지 않는다", async () => {
  const { handleSync } = await import(moduleUrl);
  const duplicate = await handleSync(post({ events: validEvents }), {
    authenticate: () => "user-a",
    submit: () => 0,
  });
  assert.equal(duplicate.status, 200);
  assert.deepEqual(await duplicate.json(), { received: 1, inserted: 0 });

  const failed = await handleSync(post({ events: validEvents }), {
    authenticate: () => "user-a",
    submit: () => { throw new Error("db-password-do-not-expose"); },
  });
  assert.equal(failed.status, 500);
  assert.deepEqual(await failed.json(), { error: "internal_error" });
});
