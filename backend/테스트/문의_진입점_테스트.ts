import assert from "node:assert/strict";

const supabase = new URL("../supabase/", import.meta.url);

Deno.test("문의 진입점은 서버 저장·답변 RPC와 무도구 모델 어댑터를 사용한다", () => {
  const source = Deno.readTextFileSync(new URL("functions/support-chat/index.ts", supabase));
  for (const value of ["Deno.serve(", "readCloudConfig", "createCloudServices", "handleSupport",
    "create_support_request", "finish_support_request", "askModel", "OPENAI_API_KEY", "OPENAI_MODEL"]) {
    assert.ok(source.includes(value), `missing ${value}`);
  }
});

Deno.test("문의 함수에서도 JWT 검증을 유지한다", () => {
  const config = Deno.readTextFileSync(new URL("config.toml", supabase));
  assert.match(config, /\[functions\.support-chat\][\s\S]*?verify_jwt\s*=\s*true/);
  assert.doesNotMatch(config, /verify_jwt\s*=\s*false/);
});
