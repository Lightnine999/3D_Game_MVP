import assert from "node:assert/strict";

const moduleUrl = new URL("../supabase/functions/admin-support-reply/처리.ts", import.meta.url).href;
function post(body: unknown): Request {
  return new Request("https://example.invalid/functions/v1/admin-support-reply", {
    method: "POST", headers: { authorization: "Bearer admin", "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}
const valid = { threadId: "thread-1", reply: "확인했습니다.", status: "closed" };

Deno.test("관리자 답변은 JWT 관리자 ID를 DB 함수로 넘긴다", async () => {
  const { handleAdminReply } = await import(moduleUrl);
  const calls: unknown[] = [];
  const response = await handleAdminReply(post({ ...valid, admin_id: "attacker" }), {
    authenticate: () => "admin-a", isAdmin: () => true,
    reply: (adminId: string, threadId: string, message: string, status: string) => {
      calls.push({ adminId, threadId, message, status });
    },
  });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { threadId: "thread-1", status: "closed" });
  assert.deepEqual(calls, [{ adminId: "admin-a", threadId: "thread-1", message: "확인했습니다.", status: "closed" }]);
});

Deno.test("무인증·일반 사용자·잘못된 상태/답변은 쓰기 전에 거부한다", async () => {
  const { handleAdminReply } = await import(moduleUrl);
  let writes = 0;
  const deps = { authenticate: () => "user-a", isAdmin: () => false, reply: () => { writes++; } };
  assert.equal((await handleAdminReply(post(valid), deps)).status, 403);
  assert.equal((await handleAdminReply(post(valid), { ...deps, authenticate: () => null })).status, 401);
  assert.equal((await handleAdminReply(post({ ...valid, status: "admin" }), { ...deps, isAdmin: () => true })).status, 400);
  assert.equal((await handleAdminReply(post({ ...valid, reply: " " }), { ...deps, isAdmin: () => true })).status, 400);
  assert.equal(writes, 0);
});

Deno.test("DB 답변 실패는 내부 오류 내용을 공개하지 않는다", async () => {
  const { handleAdminReply } = await import(moduleUrl);
  const response = await handleAdminReply(post(valid), {
    authenticate: () => "admin-a", isAdmin: () => true,
    reply: () => { throw new Error("provider-private-detail"); },
  });
  assert.equal(response.status, 500);
  assert.deepEqual(await response.json(), { error: "internal_error" });
});
