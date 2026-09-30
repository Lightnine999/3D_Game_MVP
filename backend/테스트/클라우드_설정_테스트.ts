import assert from "node:assert/strict";

const moduleUrl = new URL("../supabase/functions/_shared/클라우드.ts", import.meta.url).href;
const values: Record<string, string> = {
  SUPABASE_URL: "https://project.supabase.co",
  SUPABASE_PUBLISHABLE_KEY: "sb_publishable_dummy",
  SUPABASE_SERVICE_ROLE_KEY: "dummy-server-key",
};

Deno.test("Cloud 설정은 공개 키와 서버 전용 키를 분리해서 읽는다", async () => {
  const { readCloudConfig } = await import(moduleUrl);
  const config = readCloudConfig((name: string) => values[name]);
  assert.deepEqual(config, {
    url: "https://project.supabase.co", publicKey: "sb_publishable_dummy", serviceKey: "dummy-server-key",
  });
});

Deno.test("URL·공개 키·서비스 키 중 하나라도 없으면 연결을 거부한다", async () => {
  const { readCloudConfig } = await import(moduleUrl);
  for (const missing of Object.keys(values)) {
    assert.throws(
      () => readCloudConfig((name: string) => name === missing ? undefined : values[name]),
      /server_not_configured/,
    );
  }
});
