import assert from "node:assert/strict";

const moduleUrl = new URL("../supabase/functions/support-chat/처리.ts", import.meta.url).href;
function post(body: unknown): Request {
  return new Request("https://example.invalid/functions/v1/support-chat", {
    method: "POST", headers: { "content-type": "application/json", authorization: "Bearer session" },
    body: JSON.stringify(body),
  });
}

Deno.test("버그·결제 문의는 AI 호출 없이 사람 확인으로 저장한다", async () => {
  const { handleSupport } = await import(moduleUrl);
  let aiCalls = 0;
  const saved: unknown[] = [];
  const deps = {
    authenticate: () => "user-a", canAnswer: () => true,
    create: (userId: string, input: unknown) => { saved.push({ userId, input }); return "thread-1"; },
    answer: () => { aiCalls++; return Promise.resolve({ status: "ai_answered" as const, reply: "should not run" }); },
    finish: (userId: string, threadId: string, status: string, reply: string) => { saved.push({ userId, threadId, status, reply }); },
  };
  const bug = await handleSupport(post({ kind: "bug", message: "멈춤", bug_context: { app_version: "0.1.0" } }), deps);
  assert.equal(bug.status, 202);
  assert.deepEqual(await bug.json(), { threadId: "thread-1", status: "needs_human", reply: "팀에 전달했어요" });
  assert.equal(aiCalls, 0);
  assert.equal(saved.length, 2);
  const payment = await handleSupport(post({ kind: "question", message: "환불해줘" }), deps);
  assert.equal(payment.status, 202);
  assert.equal(aiCalls, 0);
});

Deno.test("일반 질문은 답변을 저장하고 본문 상태로 구분한다", async () => {
  const { handleSupport } = await import(moduleUrl);
  const finished: unknown[] = [];
  const response = await handleSupport(post({ kind: "question", message: "탄약은 어디서 얻나요?" }), {
    authenticate: () => "user-a", canAnswer: () => true, create: () => "thread-2",
    answer: () => Promise.resolve({ status: "ai_answered" as const, reply: "보급 상자에서 얻습니다." }),
    finish: (_user: string, _thread: string, status: string, reply: string) => { finished.push({ status, reply }); },
  });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { threadId: "thread-2", status: "ai_answered", reply: "보급 상자에서 얻습니다." });
  assert.deepEqual(finished, [{ status: "ai_answered", reply: "보급 상자에서 얻습니다." }]);
});

Deno.test("모델이 모른다고 판단하면 팀 전달 상태와 안전한 안내를 저장한다", async () => {
  const { handleSupport } = await import(moduleUrl);
  const finished: unknown[] = [];
  const response = await handleSupport(post({ kind: "question", message: "아직 구현되지 않은 숨겨진 무기는?" }), {
    authenticate: () => "user-a", canAnswer: () => true, create: () => "thread-unknown",
    answer: () => Promise.resolve({ status: "needs_human" as const, reply: "제가 모르는 내용이에요" }),
    finish: (_user: string, _thread: string, status: string, reply: string) => { finished.push({ status, reply }); },
  });
  assert.equal(response.status, 202);
  assert.deepEqual(await response.json(), {
    threadId: "thread-unknown", status: "needs_human", reply: "팀에 전달했어요",
  });
  assert.deepEqual(finished, [{ status: "needs_human", reply: "팀에 전달했어요" }]);
});

Deno.test("키 없음·무인증·한도 초과는 필요한 쓰기 전에 거부한다", async () => {
  const { handleSupport } = await import(moduleUrl);
  let writes = 0;
  const deps = {
    authenticate: () => "user-a", canAnswer: () => false,
    create: () => { writes++; return "thread-3"; },
    answer: () => Promise.resolve({ status: "ai_answered" as const, reply: "not used" }), finish: () => { writes++; },
  };
  const noKey = await handleSupport(post({ kind: "question", message: "조작법?" }), deps);
  assert.equal(noKey.status, 503);
  assert.deepEqual(await noKey.json(), { error: "chat_key_missing" });
  assert.equal((await handleSupport(post({ kind: "question", message: "조작법?" }), { ...deps, authenticate: () => null })).status, 401);
  assert.equal((await handleSupport(post({ kind: "question", message: " " }), { ...deps, canAnswer: () => true })).status, 400);
  assert.equal(writes, 0);
  const limited = await handleSupport(post({ kind: "bug", message: "오류" }), {
    ...deps, create: () => { throw new Error("daily_limit_reached"); },
  });
  assert.equal(limited.status, 429);
});

Deno.test("AI 장애는 개인정보 오류를 노출하지 않고 사람 확인으로 넘긴다", async () => {
  const { handleSupport } = await import(moduleUrl);
  const finished: string[] = [];
  const response = await handleSupport(post({ kind: "question", message: "알 수 없는 문제" }), {
    authenticate: () => "user-a", canAnswer: () => true, create: () => "thread-4",
    answer: () => Promise.reject(new Error("provider-private-detail")),
    finish: (_user: string, _thread: string, status: string) => { finished.push(status); },
  });
  assert.equal(response.status, 202);
  assert.deepEqual(await response.json(), { threadId: "thread-4", status: "needs_human", reply: "팀에 전달했어요" });
  assert.deepEqual(finished, ["needs_human"]);
});
