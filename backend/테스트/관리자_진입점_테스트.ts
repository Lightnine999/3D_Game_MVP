import assert from "node:assert/strict";

const supabase = new URL("../supabase/", import.meta.url);

Deno.test("관리자 진입점은 JWT 역할 확인 후 제한된 보기·답변만 실행한다", () => {
  const overview = Deno.readTextFileSync(new URL("functions/admin-overview/index.ts", supabase));
  const reply = Deno.readTextFileSync(new URL("functions/admin-support-reply/index.ts", supabase));
  for (const source of [overview, reply]) {
    assert.match(source, /Deno\.serve\(/);
    assert.match(source, /readCloudConfig/);
    assert.match(source, /createCloudServices/);
    assert.match(source, /\.eq\("id", userId\)/);
    assert.match(source, /role === "admin"/);
  }
  assert.match(overview, /handleAdminOverview/);
  assert.match(overview, /admin\.from\(view\)/);
  assert.match(reply, /handleAdminReply/);
  assert.match(reply, /admin_reply/);
});

Deno.test("관리자 두 함수 모두 JWT 검증을 켠다", () => {
  const config = Deno.readTextFileSync(new URL("config.toml", supabase));
  assert.match(config, /\[functions\.admin-overview\][\s\S]*?verify_jwt\s*=\s*true/);
  assert.match(config, /\[functions\.admin-support-reply\][\s\S]*?verify_jwt\s*=\s*true/);
  assert.doesNotMatch(config, /verify_jwt\s*=\s*false/);
});
