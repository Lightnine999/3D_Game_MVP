import assert from "node:assert/strict";

const moduleUrl = new URL("../supabase/functions/admin-overview/처리.ts", import.meta.url).href;
function post(body: unknown): Request {
  return new Request("https://example.invalid/functions/v1/admin-overview", {
    method: "POST", headers: { authorization: "Bearer admin", "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

Deno.test("관리자 JWT만 허용된 보기에서 마스킹된 항목을 조회한다", async () => {
  const { handleAdminOverview } = await import(moduleUrl);
  const views: string[] = [];
  const response = await handleAdminOverview(post({ section: "members", table: "auth.users" }), {
    authenticate: () => "admin-a", isAdmin: () => true,
    list: (view: string) => { views.push(view); return [{ user_id: "user-a", email_masked: "ab***@example.com" }]; },
  });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { section: "members", items: [{ user_id: "user-a", email_masked: "ab***@example.com" }] });
  assert.deepEqual(views, ["admin_members"]);
});

Deno.test("일반 사용자·무인증·임의 보기 이름은 DB 조회 전에 거부된다", async () => {
  const { handleAdminOverview } = await import(moduleUrl);
  let reads = 0;
  const deps = { authenticate: () => "user-a", isAdmin: () => false, list: () => { reads++; return []; } };
  assert.equal((await handleAdminOverview(post({ section: "members" }), deps)).status, 403);
  assert.equal((await handleAdminOverview(post({ section: "members" }), { ...deps, authenticate: () => null })).status, 401);
  assert.equal((await handleAdminOverview(post({ section: "auth.users" }), { ...deps, isAdmin: () => true })).status, 400);
  assert.equal(reads, 0);
});

Deno.test("관리자 조회 장애에 원문을 반환하지 않는다", async () => {
  const { handleAdminOverview } = await import(moduleUrl);
  const response = await handleAdminOverview(post({ section: "support" }), {
    authenticate: () => "admin-a", isAdmin: () => true,
    list: () => { throw new Error("db-private-detail"); },
  });
  assert.equal(response.status, 500);
  assert.deepEqual(await response.json(), { error: "internal_error" });
});
