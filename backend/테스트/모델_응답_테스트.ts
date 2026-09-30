import assert from "node:assert/strict";

const moduleUrl = new URL("../supabase/functions/_shared/모델.ts", import.meta.url).href;
const responseBody = { status: "completed", output: [{ type: "message", content: [{
  type: "output_text", text: JSON.stringify({ status: "ai_answered", reply: "검증용 문구는 파란 구름 42입니다." }),
}] }] };

Deno.test("서버 전용 Responses API로 도구 없는 구조화 답변을 요청한다", async () => {
  const { askModel } = await import(moduleUrl);
  let calls = 0;
  const reply = await askModel("dummy-key", "dummy-model", "테스트 안내 문구가 뭐야?", (url: string, init: RequestInit) => {
    calls++;
    assert.equal(url, "https://api.openai.com/v1/responses");
    assert.equal(init.method, "POST");
    assert.equal(new Headers(init.headers).get("Authorization"), "Bearer dummy-key");
    const body = JSON.parse(String(init.body));
    assert.equal(body.model, "dummy-model");
    assert.equal(body.input, "테스트 안내 문구가 뭐야?");
    assert.equal(body.store, false);
    assert.equal(Array.isArray(body.tools) ? body.tools.length : 0, 0);
    assert.equal(typeof body.instructions, "string");
    assert.match(body.instructions, /테스트 전용/);
    assert.match(body.instructions, /파란 구름 42/);
    assert.doesNotMatch(body.instructions, /1,000m|권총은 시작 탄약이 0발/);
    assert.equal(body.text.format.type, "json_schema");
    assert.equal(body.text.format.strict, true);
    assert.deepEqual(body.text.format.schema.required, ["status", "reply"]);
    return Promise.resolve(new Response(JSON.stringify(responseBody), { status: 200 }));
  });
  assert.deepEqual(reply, { status: "ai_answered", reply: "검증용 문구는 파란 구름 42입니다." });
  assert.equal(calls, 1);
});

Deno.test("모르는 질문은 구조화된 사람 전달 상태를 보존한다", async () => {
  const { askModel } = await import(moduleUrl);
  const body = { status: "completed", output: [{ type: "message", content: [{ type: "output_text",
    text: JSON.stringify({ status: "needs_human", reply: "팀에 전달했어요" }),
  }] }] };
  const result = await askModel("dummy-key", "dummy-model", "확인되지 않은 게임 규칙?", () =>
    Promise.resolve(new Response(JSON.stringify(body), { status: 200 })));
  assert.deepEqual(result, { status: "needs_human", reply: "팀에 전달했어요" });
});

Deno.test("완료되지 않았거나 형식이 잘못된 답변은 사용하지 않는다", async () => {
  const { askModel } = await import(moduleUrl);
  for (const body of [
    { ...responseBody, status: "incomplete" },
    { ...responseBody, output: [{ type: "message", content: [{ type: "output_text", text: "{}" }] }] },
  ]) {
    await assert.rejects(() => askModel("dummy-key", "dummy-model", "질문", () =>
      Promise.resolve(new Response(JSON.stringify(body), { status: 200 }))));
  }
});

Deno.test("키·모델이 없거나 제공자 응답이 실패하면 내부 내용을 노출하지 않는다", async () => {
  const { askModel } = await import(moduleUrl);
  let calls = 0;
  const fetcher = () => { calls++; return Promise.resolve(new Response("{}", { status: 200 })); };
  await assert.rejects(() => askModel("", "dummy-model", "질문", fetcher), /chat_key_missing/);
  await assert.rejects(() => askModel("dummy-key", "", "질문", fetcher), /chat_key_missing/);
  assert.equal(calls, 0);
  await assert.rejects(
    () => askModel("dummy-key", "dummy-model", "질문", () => Promise.resolve(new Response("provider-private", { status: 401 }))),
    /^Error: model_request_failed$/,
  );
  await assert.rejects(
    () => askModel("dummy-key", "dummy-model", "질문", () => Promise.resolve(new Response("{}", { status: 200 }))),
    /^Error: empty_model_reply$/,
  );
});
