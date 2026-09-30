import assert from "node:assert/strict";

const moduleUrl = new URL("../supabase/functions/delete-account/처리.ts", import.meta.url).href;
function post(body: unknown): Request {
  return new Request("https://example.invalid/functions/v1/delete-account", {
    method: "POST", headers: { "content-type": "application/json", authorization: "Bearer session" },
    body: JSON.stringify(body),
  });
}

Deno.test("명시적 확인 뒤에는 JWT 본인만 삭제하고 클라이언트 user_id를 무시한다", async () => {
  const { handleDeleteAccount } = await import(moduleUrl);
  const deleted: string[] = [];
  const response = await handleDeleteAccount(post({ confirm: true, user_id: "other" }), {
    authenticate: () => "user-a",
    deleteUser: (id: string) => { deleted.push(id); },
  });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { status: "deleted" });
  assert.deepEqual(deleted, ["user-a"]);
});

Deno.test("무인증·확인 누락·GET 요청에서는 계정을 삭제하지 않는다", async () => {
  const { handleDeleteAccount } = await import(moduleUrl);
  let deleted = 0;
  const deleteUser = () => { deleted++; };
  assert.equal((await handleDeleteAccount(post({ confirm: true }), {
    authenticate: () => null, deleteUser,
  })).status, 401);
  const deps = { authenticate: () => "user-a", deleteUser };
  const noConfirm = await handleDeleteAccount(post({ confirm: false }), deps);
  assert.equal(noConfirm.status, 400);
  assert.deepEqual(await noConfirm.json(), { error: "confirmation_required" });
  assert.equal((await handleDeleteAccount(new Request("https://example.invalid/functions/v1/delete-account"), deps)).status, 405);
  assert.equal(deleted, 0);
});

Deno.test("제공자 삭제 실패의 원문을 응답하지 않는다", async () => {
  const { handleDeleteAccount } = await import(moduleUrl);
  const response = await handleDeleteAccount(post({ confirm: true }), {
    authenticate: () => "user-a", deleteUser: () => { throw new Error("provider-private-detail"); },
  });
  assert.equal(response.status, 500);
  assert.deepEqual(await response.json(), { error: "internal_error" });
});
