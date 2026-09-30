import assert from "node:assert/strict";

const moduleUrl = new URL("../supabase/functions/_shared/토스.ts", import.meta.url).href;
const request = { paymentKey: "payment-dummy", orderId: "order_001", amount: 1100 };
const approved = { paymentKey: "payment-dummy", orderId: "order_001", totalAmount: 1100, status: "DONE" };

Deno.test("테스트 시크릿으로 서버 승인 URL·금액·멱등키를 정확히 보낸다", async () => {
  const { confirmPaymentWithToss } = await import(moduleUrl);
  let calls = 0;
  const result = await confirmPaymentWithToss("test_sk_dummy", request, (url: string, init: RequestInit) => {
    calls++;
    assert.equal(url, "https://api.tosspayments.com/v1/payments/confirm");
    assert.equal(init.method, "POST");
    const headers = new Headers(init.headers);
    assert.equal(headers.get("Idempotency-Key"), request.orderId);
    assert.equal(headers.get("Authorization"), `Basic ${btoa("test_sk_dummy:")}`);
    assert.deepEqual(JSON.parse(String(init.body)), request);
    return Promise.resolve(new Response(JSON.stringify(approved), { status: 200 }));
  });
  assert.equal(calls, 1);
  assert.deepEqual(result, approved);
});

Deno.test("라이브 키·빈 키·잘못된 승인 요청은 공급자 호출 전에 거부한다", async () => {
  const { confirmPaymentWithToss } = await import(moduleUrl);
  let calls = 0;
  const fetcher = () => { calls++; return Promise.resolve(new Response("{}", { status: 200 })); };
  await assert.rejects(() => confirmPaymentWithToss("live_sk_dummy", request, fetcher), /test_secret_required/);
  await assert.rejects(() => confirmPaymentWithToss("", request, fetcher), /test_secret_required/);
  await assert.rejects(() => confirmPaymentWithToss("test_sk_dummy", { ...request, amount: -1 }, fetcher), /invalid_confirmation_request/);
  assert.equal(calls, 0);
});

Deno.test("공급자 오류·누락 응답은 승인으로 오인하거나 내용이 노출되지 않는다", async () => {
  const { confirmPaymentWithToss } = await import(moduleUrl);
  await assert.rejects(
    () => confirmPaymentWithToss("test_sk_dummy", request, () => Promise.resolve(new Response("provider-sensitive", { status: 400 }))),
    /^Error: toss_confirmation_rejected$/,
  );
  await assert.rejects(
    () => confirmPaymentWithToss("test_sk_dummy", request, () => Promise.resolve(new Response("{}", { status: 200 }))),
    /^Error: invalid_toss_response$/,
  );
});
