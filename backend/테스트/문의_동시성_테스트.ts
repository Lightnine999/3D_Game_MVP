import assert from "node:assert/strict";
import { handleSupport, type SupportDependencies } from "../supabase/functions/support-chat/처리.ts";
const id = "abcdefab-1234-4abc-8def-abcdefabcdef";
const post = (message: string) => new Request("https://example.invalid", {
  method: "POST", body: JSON.stringify({ kind: "question", message, threadId: id.toUpperCase() }),
});

Deno.test("동일 스레드 병렬 요청은 busy이며 이력·완료·해제는 획득 토큰에 묶인다", async () => {
  let owner: string | undefined;
  let question = "";
  let writes = 0;
  let ready!: () => void;
  let resume!: () => void;
  const entered = new Promise<void>((r) => ready = r);
  const gate = new Promise<void>((r) => resume = r);
  const finished: string[] = [];
  const released: string[] = [];
  const deps = {
    authenticate: () => "user", canAnswer: () => true, create: () => id,
    append: (_u: string, thread: string, message: string, token?: string) => {
      assert.equal(thread, id);
      assert.ok(token, "append requires request ownership token");
      if (owner) throw new Error("thread_busy");
      owner = token; question = message; writes++; return id;
    },
    history: (_u: string, _t: string, token?: string) => {
      assert.equal(token, owner); return [{ role: "user" as const, content: question }];
    },
    answer: async (message: string, history?: { content: string }[]) => {
      ready(); await gate; assert.equal(history?.at(-1)?.content, message);
      return { status: "ai_answered" as const, reply: message + " 답변" };
    },
    finish: (_u: string, _t: string, _s: string, reply: string, token?: string) => {
      assert.equal(token, owner); finished.push(reply);
    },
    release: (_u: string, _t: string, token: string) => {
      assert.equal(token, owner); released.push(token); owner = undefined;
    },
  };
  const a = handleSupport(post("A"), deps as SupportDependencies);
  // Race-safe even before implementation: a failing request must not hang the test.
  await Promise.race([entered, a]);
  const b = await handleSupport(post("B"), deps as SupportDependencies);
  resume();
  const result = await a;
  assert.equal(result.status, 200);
  assert.equal(b.status, 409);
  assert.deepEqual(await b.json(), { error: "thread_busy" });
  assert.equal(writes, 1);
  assert.deepEqual(finished, ["A 답변"]);
  assert.equal(released.length, 1);
});

Deno.test("만료 후 새 요청이 소유권을 가져도 느린 이전 답변·해제는 새 요청을 변경하지 않는다", async () => {
  // Deterministic RPC contract fake, NOT a PostgreSQL concurrency execution.
  let owner: string | undefined;
  let expiry = 0;
  let now = 0;
  let question = "";
  const gates = new Map<string, () => void>();
  const entered = new Map<string, () => void>();
  const readyA = new Promise<void>((r) => entered.set("A", r));
  const readyB = new Promise<void>((r) => entered.set("B", r));
  const saved: string[] = [];
  const deps: SupportDependencies = {
    authenticate: () => "user", canAnswer: () => true, create: () => id,
    append: (_u, _t, message, token) => {
      if (owner && expiry > now) throw new Error("thread_busy");
      owner = token; expiry = now + 120; question = message; return id;
    },
    history: (_u, _t, token) => {
      if (owner !== token || expiry <= now) throw new Error("support_request_expired");
      return [{ role: "user", content: question }];
    },
    answer: async (message, history) => {
      const gate = new Promise<void>((r) => gates.set(message, r));
      entered.get(message)!();
      await gate;
      assert.equal(history?.at(-1)?.content, message);
      return { status: "ai_answered", reply: message + " 답변" };
    },
    finish: (_u, _t, _s, reply, token) => {
      if (owner !== token || expiry <= now) throw new Error("support_request_expired");
      saved.push(reply); owner = undefined;
    },
    release: (_u, _t, token) => { if (owner === token) owner = undefined; },
  };
  const a = handleSupport(post("A"), deps);
  await readyA;
  now = 121;
  const b = handleSupport(post("B"), deps);
  await readyB;
  const newOwner = owner;
  gates.get("A")!();
  assert.equal((await a).status, 409);
  assert.equal(owner, newOwner);
  gates.get("B")!();
  assert.equal((await b).status, 200);
  assert.deepEqual(saved, ["B 답변"]);
  assert.equal(owner, undefined);
});

Deno.test("모델 장애는 사람 전달로 완료하고 해제 장애는 성공 응답을 덮지 않는다", async () => {
  let completed = "";
  let released = false;
  const response = await handleSupport(post("A"), {
    authenticate: () => "user", canAnswer: () => true, create: () => id,
    append: () => id,
    answer: () => Promise.reject(new Error("private_provider_error")),
    finish: (_u, _t, status) => { completed = status; },
    release: () => { released = true; throw new Error("private_database_error"); },
  });
  assert.equal(response.status, 202);
  assert.equal(completed, "needs_human");
  assert.equal(released, true);
  assert.deepEqual(await response.json(), { threadId: id, status: "needs_human", reply: "팀에 전달했어요" });
});

Deno.test("완료 실패도 소유 토큰을 해제하고 만료 요청은 안정된 409를 반환한다", async () => {
  const tokens: string[] = [];
  let acquired: string | undefined;
  const response = await handleSupport(post("A"), {
    authenticate: () => "user", canAnswer: () => true, create: () => id,
    append: (_u: string, _t: string, _m: string, token?: string) => { acquired = token; return id; },
    answer: async () => ({ status: "ai_answered" as const, reply: "답" }),
    finish: () => { throw new Error("support_request_expired"); },
    release: (_u: string, _t: string, token: string) => { tokens.push(token); },
  } as SupportDependencies);
  assert.equal(response.status, 409);
  assert.deepEqual(await response.json(), { error: "support_request_expired" });
  assert.ok(acquired);
  assert.deepEqual(tokens, [acquired]);
});
