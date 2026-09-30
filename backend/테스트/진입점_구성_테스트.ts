import assert from "node:assert/strict";

const supabase = new URL("../supabase/", import.meta.url);

Deno.test("프로필·동기화 진입점은 공통 인증과 해당 DB RPC에 연결된다", () => {
  for (const [name, handler, rpc] of [
    ["ensure-profile", "handleEnsureProfile", "ensure_profile"],
    ["sync-progress", "handleSync", "sync_submit"],
  ]) {
    const source = Deno.readTextFileSync(new URL(`functions/${name}/index.ts`, supabase));
    assert.match(source, /Deno\.serve\(/);
    assert.match(source, /readCloudConfig/);
    assert.match(source, /createCloudServices/);
    assert.match(source, new RegExp(handler));
    assert.match(source, new RegExp(rpc));
  }
});

Deno.test("본편 함수는 JWT 검증을 끄지 않는다", () => {
  const config = Deno.readTextFileSync(new URL("config.toml", supabase));
  assert.match(config, /\[functions\.ensure-profile\][\s\S]*?verify_jwt\s*=\s*true/);
  assert.match(config, /\[functions\.sync-progress\][\s\S]*?verify_jwt\s*=\s*true/);
  assert.doesNotMatch(config, /verify_jwt\s*=\s*false/);
});
