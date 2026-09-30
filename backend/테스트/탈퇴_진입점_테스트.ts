import assert from "node:assert/strict";

const supabase = new URL("../supabase/", import.meta.url);

Deno.test("탈퇴 진입점은 사용자 인증 뒤 Admin API의 본인 삭제만 호출한다", () => {
  const source = Deno.readTextFileSync(new URL("functions/delete-account/index.ts", supabase));
  assert.match(source, /Deno\.serve\(/);
  assert.match(source, /readCloudConfig/);
  assert.match(source, /createCloudServices/);
  assert.match(source, /handleDeleteAccount/);
  assert.match(source, /admin\.auth\.admin\.deleteUser\(userId\)/);
});

Deno.test("탈퇴 함수도 JWT 검증을 끄지 않는다", () => {
  const config = Deno.readTextFileSync(new URL("config.toml", supabase));
  assert.match(config, /\[functions\.delete-account\][\s\S]*?verify_jwt\s*=\s*true/);
  assert.doesNotMatch(config, /verify_jwt\s*=\s*false/);
});
