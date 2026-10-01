import assert from "node:assert/strict";

const moduleUrl = new URL("../supabase/functions/confirm-toss-payment/처리.ts", import.meta.url).href;
const order = { order_id: "order_001", user_id: "user-a", product_id: "ammo_start_pack", amount: 1100, status: "ready" };
const requestBody = { paymentKey: "test-payment", orderId: "order_001", amount: 1100 };
const approved = { paymentKey: "test-payment", orderId: "order_001", totalAmount: 1100, status: "DONE" };
function post(body: unknown): Request {
  return new Request("https://example.invalid/functions/v1/confirm-toss-payment", {
    method: "POST", headers: { authorization: "Bearer test-session", "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

Deno.test("세 패키지와 두 기존 단품의 ready 주문은 저장 금액으로 승인하고 응답 계약을 유지한다", async () => {
  const { handleConfirmPayment } = await import(moduleUrl);
  for (const [productId, amount] of [
    ["pack_survival_kit", 1100], ["pack_one_more", 3300], ["pack_legend", 5500],
    ["ammo_start_pack", 1100], ["supporter_badge", 3300],
  ] as const) {
    let grants = 0;
    const saved = { ...order, product_id: productId, amount };
    const response = await handleConfirmPayment(post({ ...requestBody, amount, components: { revive: 999 } }), {
      authenticate: () => "user-a", findOrder: () => saved,
      requestApproval: (attempt: { amount: number }) => {
        assert.equal(attempt.amount, amount);
        return Promise.resolve({ ...approved, totalAmount: amount });
      },
      grant: (stored: typeof saved) => {
        assert.deepEqual(stored, saved);
        grants++;
        return Promise.resolve("paid" as const);
      },
    });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { status: "paid", orderId: requestBody.orderId });
    assert.equal(grants, 1);
  }
});

Deno.test("패키지 기지급 재요청은 Toss 승인과 지급 RPC를 다시 호출하지 않는다", async () => {
  const { handleConfirmPayment } = await import(moduleUrl);
  for (const [productId, amount] of [["pack_survival_kit", 1100], ["pack_one_more", 3300], ["pack_legend", 5500]] as const) {
    let calls = 0;
    const deps = {
      authenticate: () => "user-a",
      findOrder: () => ({ ...order, product_id: productId, amount, status: "paid", payment_key: requestBody.paymentKey }),
      requestApproval: () => { calls++; throw new Error("must not approve"); },
      grant: () => { calls++; throw new Error("must not grant"); },
    };
    const same = await handleConfirmPayment(post({ ...requestBody, amount }), deps);
    assert.equal(same.status, 200);
    assert.deepEqual(await same.json(), { status: "already_paid", orderId: requestBody.orderId });
    const conflict = await handleConfirmPayment(post({ ...requestBody, amount, paymentKey: "other" }), deps);
    assert.equal(conflict.status, 409);
    assert.equal(calls, 0);
  }
});

Deno.test("정상 승인도 서버 DB 지급 결과를 받아야 paid를 반환한다", async () => {
  const { handleConfirmPayment } = await import(moduleUrl);
  let approvals = 0, grants = 0;
  const response = await handleConfirmPayment(post(requestBody), {
    authenticate: () => "user-a",
    findOrder: () => order,
    requestApproval: () => { approvals++; return Promise.resolve(approved); },
    grant: () => { grants++; return Promise.resolve("paid" as const); },
  });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { status: "paid", orderId: "order_001" });
  assert.equal(approvals, 1);
  assert.equal(grants, 1);
});

Deno.test("타인 주문과 금액 변조는 공급자·DB 지급 전에 거부한다", async () => {
  const { handleConfirmPayment } = await import(moduleUrl);
  let writes = 0;
  const deps = {
    authenticate: () => "user-a", findOrder: () => order,
    requestApproval: () => { writes++; return Promise.resolve(approved); },
    grant: () => { writes++; return Promise.resolve("paid" as const); },
  };
  const tampered = await handleConfirmPayment(post({ ...requestBody, amount: 100 }), deps);
  assert.equal(tampered.status, 400);
  assert.deepEqual(await tampered.json(), { error: "amount_mismatch" });
  const foreign = await handleConfirmPayment(post(requestBody), { ...deps, authenticate: () => "user-b" });
  assert.equal(foreign.status, 404);
  assert.equal(writes, 0);
});

Deno.test("기지급 주문은 같은 결제 키만 재지급 없이 돌려준다", async () => {
  const { handleConfirmPayment } = await import(moduleUrl);
  let calls = 0;
  const deps = {
    authenticate: () => "user-a", findOrder: () => ({ ...order, status: "paid", payment_key: "test-payment" }),
    requestApproval: () => { calls++; return Promise.resolve(approved); },
    grant: () => { calls++; return Promise.resolve("paid" as const); },
  };
  const same = await handleConfirmPayment(post(requestBody), deps);
  assert.equal(same.status, 200);
  assert.deepEqual(await same.json(), { status: "already_paid", orderId: "order_001" });
  const different = await handleConfirmPayment(post({ ...requestBody, paymentKey: "other" }), deps);
  assert.equal(different.status, 409);
  assert.equal(calls, 0);
});

Deno.test("키 누락·Toss 불일치·DB 오류의 세부 내용은 노출하지 않는다", async () => {
  const { handleConfirmPayment } = await import(moduleUrl);
  const base = {
    authenticate: () => "user-a", findOrder: () => order,
    requestApproval: () => Promise.resolve(approved), grant: () => Promise.resolve("paid" as const),
  };
  const noKey = await handleConfirmPayment(post(requestBody), {
    ...base, requestApproval: () => Promise.reject(new Error("test_secret_required")),
  });
  assert.equal(noKey.status, 503);
  assert.deepEqual(await noKey.json(), { error: "test_key_missing" });

  const mismatch = await handleConfirmPayment(post(requestBody), {
    ...base, requestApproval: () => Promise.resolve({ ...approved, totalAmount: 99 }),
  });
  assert.equal(mismatch.status, 502);
  assert.deepEqual(await mismatch.json(), { error: "provider_mismatch" });

  const database = await handleConfirmPayment(post(requestBody), {
    ...base, grant: () => Promise.reject(new Error("db-sensitive-error")),
  });
  assert.equal(database.status, 500);
  assert.deepEqual(await database.json(), { error: "internal_error" });
});
