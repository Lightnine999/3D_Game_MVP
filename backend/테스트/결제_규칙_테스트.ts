import assert from "node:assert/strict";

const moduleUrl = new URL("../supabase/functions/_shared/결제.ts", import.meta.url).href;
const order = { order_id: "order_001", user_id: "user-a", product_id: "ammo_start_pack", amount: 1100, status: "ready" };
const request = { paymentKey: "test-payment", orderId: "order_001", amount: 1100 };
const approved = { paymentKey: "test-payment", orderId: "order_001", totalAmount: 1100, status: "DONE" };

Deno.test("서버 가격표 외 상품은 주문할 수 없다", async () => {
  const { priceFor } = await import(moduleUrl);
  assert.equal(priceFor("ammo_start_pack")?.amount, 1100);
  assert.equal(priceFor("supporter_badge")?.amount, 3300);
  assert.equal(priceFor("unknown"), null);
});

Deno.test("타인 주문·변조 금액은 Toss와 DB 지급 전에 거부한다", async () => {
  const { confirmOnce } = await import(moduleUrl);
  let providerCalls = 0;
  let grantCalls = 0;
  const deps = {
    requestApproval: () => { providerCalls++; return Promise.resolve(approved); },
    grant: () => { grantCalls++; return Promise.resolve("paid" as const); },
  };

  assert.equal(await confirmOnce(order, "user-b", request, deps), "not_owner");
  assert.equal(await confirmOnce(order, "user-a", { ...request, amount: 100 }, deps), "amount_mismatch");
  assert.equal(providerCalls, 0);
  assert.equal(grantCalls, 0);
});

Deno.test("Toss 승인 결과의 키·주문·금액·상태가 다르면 지급하지 않는다", async () => {
  const { confirmOnce } = await import(moduleUrl);
  let grants = 0;
  for (const response of [
    { ...approved, paymentKey: "other" },
    { ...approved, orderId: "other" },
    { ...approved, totalAmount: 10 },
    { ...approved, status: "READY" },
  ]) {
    assert.equal(await confirmOnce(order, "user-a", request, {
      requestApproval: () => Promise.resolve(response),
      grant: () => { grants++; return Promise.resolve("paid" as const); },
    }), "provider_mismatch");
  }
  assert.equal(grants, 0);
});

Deno.test("승인 성공은 DB의 1회 지급 결과가 있어야 paid가 된다", async () => {
  const { confirmOnce } = await import(moduleUrl);
  let grants = 0;
  const result = await confirmOnce(order, "user-a", request, {
    requestApproval: () => Promise.resolve(approved),
    grant: () => { grants++; return Promise.resolve("paid" as const); },
  });
  assert.equal(result, "paid");
  assert.equal(grants, 1);
});

Deno.test("이미 지급된 주문은 같은 결제 키만 재지급 없이 인정한다", async () => {
  const { confirmOnce } = await import(moduleUrl);
  let providerCalls = 0;
  let grantCalls = 0;
  const deps = {
    requestApproval: () => { providerCalls++; return Promise.resolve(approved); },
    grant: () => { grantCalls++; return Promise.resolve("paid" as const); },
  };
  const settled = { ...order, status: "paid", payment_key: "test-payment" };

  assert.equal(await confirmOnce(settled, "user-a", request, deps), "already_paid");
  assert.equal(await confirmOnce(settled, "user-a", { ...request, paymentKey: "other" }, deps), "already_paid_conflict");
  assert.equal(providerCalls, 0);
  assert.equal(grantCalls, 0);
});
