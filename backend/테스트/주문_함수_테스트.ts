import assert from "node:assert/strict";

const moduleUrl = new URL("../supabase/functions/create-toss-order/처리.ts", import.meta.url).href;
function post(body: unknown): Request {
  return new Request("https://example.invalid/functions/v1/create-toss-order", {
    method: "POST", headers: { "content-type": "application/json", authorization: "Bearer session" },
    body: JSON.stringify(body),
  });
}

Deno.test("서버가 본인 주문 ID·금액을 결정하고 클라이언트 user_id를 무시한다", async () => {
  const { handleCreateOrder } = await import(moduleUrl);
  const saved: Array<Record<string, unknown>> = [];
  const response = await handleCreateOrder(post({ product_id: "ammo_start_pack", user_id: "attacker" }), {
    authenticate: () => "user-a",
    insert: (order: Record<string, unknown>) => { saved.push(order); return order; },
  });
  const data = await response.json();
  assert.equal(response.status, 201);
  assert.match(data.orderId, /^[0-9a-f-]{36}$/);
  assert.deepEqual({ productId: data.productId, amount: data.amount, status: data.status },
    { productId: "ammo_start_pack", amount: 1100, status: "ready" });
  assert.equal(saved.length, 1);
  assert.deepEqual({ user_id: saved[0].user_id, order_id: saved[0].order_id, amount: saved[0].amount },
    { user_id: "user-a", order_id: data.orderId, amount: 1100 });
});

Deno.test("미인증·알 수 없는 상품·앱에서 보낸 금액은 DB 저장 전에 거부한다", async () => {
  const { handleCreateOrder } = await import(moduleUrl);
  let writes = 0;
  const insert = () => { writes++; throw new Error("must not write"); };
  assert.equal((await handleCreateOrder(post({ product_id: "ammo_start_pack" }), {
    authenticate: () => null, insert,
  })).status, 401);
  const deps = { authenticate: () => "user-a", insert };
  assert.equal((await handleCreateOrder(post({ product_id: "unknown" }), deps)).status, 400);
  const tampered = await handleCreateOrder(post({ product_id: "ammo_start_pack", amount: 1 }), deps);
  assert.equal(tampered.status, 400);
  assert.deepEqual(await tampered.json(), { error: "client_amount_forbidden" });
  assert.equal(writes, 0);
});

Deno.test("DB 장애는 내부 내용을 공개하지 않는다", async () => {
  const { handleCreateOrder } = await import(moduleUrl);
  const response = await handleCreateOrder(post({ product_id: "supporter_badge" }), {
    authenticate: () => "user-a", insert: () => { throw new Error("server-secret-text"); },
  });
  assert.equal(response.status, 500);
  assert.deepEqual(await response.json(), { error: "internal_error" });
});
