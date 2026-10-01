import assert from "node:assert/strict";

const moduleUrl = new URL("../supabase/functions/_shared/문의.ts", import.meta.url).href;

Deno.test("일반 질문과 버그 제보의 본문을 제한·정규화한다", async () => {
  const { validateSupportRequest } = await import(moduleUrl);
  assert.deepEqual(validateSupportRequest({ kind: "question", message: "  탄약은 어디서 얻나요?  " }), {
    kind: "question", message: "탄약은 어디서 얻나요?", bugContext: null, threadId: null,
  });
  assert.deepEqual(validateSupportRequest({ kind: "bug", message: "진행 멈춤", bug_context: { app_version: "0.1.0" } }), {
    kind: "bug", message: "진행 멈춤", bugContext: { app_version: "0.1.0" }, threadId: null,
  });
  assert.deepEqual(validateSupportRequest({ kind: "question", message: "그 다음에는요?", threadId: "11111111-1111-4111-8111-111111111111" }), {
    kind: "question", message: "그 다음에는요?", bugContext: null, threadId: "11111111-1111-4111-8111-111111111111",
  });
});

Deno.test("비어 있는 메시지·과도한 크기·잘못된 종류/맥락은 거부한다", async () => {
  const { validateSupportRequest } = await import(moduleUrl);
  for (const input of [
    { kind: "question", message: " " },
    { kind: "question", message: "x".repeat(2001) },
    { kind: "refund", message: "문의" },
    { kind: "bug", message: "오류", bug_context: [] },
    { kind: "question", message: "문의", threadId: "other-user-thread" },
    { kind: "bug", message: "오류", threadId: "11111111-1111-4111-8111-111111111111" },
  ]) {
    assert.throws(() => validateSupportRequest(input), /invalid_support_request/);
  }
});

Deno.test("UUID 대문자는 쓰기 전에 소문자로 정규화하고 잘못된 표기는 거부한다", async () => {
  const { validateSupportRequest } = await import(moduleUrl);
  const id = "ABCDEFAB-1234-4ABC-8DEF-ABCDEFABCDEF";
  assert.equal(validateSupportRequest({ kind: "question", message: "질문", threadId: id }).threadId, id.toLowerCase());
  for (const threadId of [" " + id, id + " ", id.replaceAll("-", ""), 123]) {
    assert.throws(() => validateSupportRequest({ kind: "question", message: "질문", threadId }), /invalid_support_request/);
  }
});

Deno.test("버그·결제·환불 문의는 AI 대신 사람 확인 대상이다", async () => {
  const { needsHuman } = await import(moduleUrl);
  assert.equal(needsHuman("bug", "진행이 안 돼요"), true);
  assert.equal(needsHuman("question", "결제 취소해 주세요"), true);
  assert.equal(needsHuman("question", "refund please"), true);
  assert.equal(needsHuman("question", "탄약은 어디서 얻나요?"), false);
});
