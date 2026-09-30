import assert from "node:assert/strict";

const moduleUrl = new URL("../supabase/functions/_shared/문의.ts", import.meta.url).href;

Deno.test("일반 질문과 버그 제보의 본문을 제한·정규화한다", async () => {
  const { validateSupportRequest } = await import(moduleUrl);
  assert.deepEqual(validateSupportRequest({ kind: "question", message: "  탄약은 어디서 얻나요?  " }), {
    kind: "question", message: "탄약은 어디서 얻나요?", bugContext: null,
  });
  assert.deepEqual(validateSupportRequest({ kind: "bug", message: "진행 멈춤", bug_context: { app_version: "0.1.0" } }), {
    kind: "bug", message: "진행 멈춤", bugContext: { app_version: "0.1.0" },
  });
});

Deno.test("비어 있는 메시지·과도한 크기·잘못된 종류/맥락은 거부한다", async () => {
  const { validateSupportRequest } = await import(moduleUrl);
  for (const input of [
    { kind: "question", message: " " },
    { kind: "question", message: "x".repeat(2001) },
    { kind: "refund", message: "문의" },
    { kind: "bug", message: "오류", bug_context: [] },
  ]) {
    assert.throws(() => validateSupportRequest(input), /invalid_support_request/);
  }
});

Deno.test("버그·결제·환불 문의는 AI 대신 사람 확인 대상이다", async () => {
  const { needsHuman } = await import(moduleUrl);
  assert.equal(needsHuman("bug", "진행이 안 돼요"), true);
  assert.equal(needsHuman("question", "결제 취소해 주세요"), true);
  assert.equal(needsHuman("question", "refund please"), true);
  assert.equal(needsHuman("question", "탄약은 어디서 얻나요?"), false);
});
