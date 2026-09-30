import assert from "node:assert/strict";

const supabase = new URL("../supabase/", import.meta.url);

Deno.test("주문·승인 함수는 서버 DB 거래와 테스트 제공자에만 연결된다", () => {
  const order = Deno.readTextFileSync(new URL("functions/create-toss-order/index.ts", supabase));
  const confirm = Deno.readTextFileSync(new URL("functions/confirm-toss-payment/index.ts", supabase));
  for (const source of [order, confirm]) {
    assert.match(source, /Deno\.serve\(/);
    assert.match(source, /readCloudConfig/);
    assert.match(source, /createCloudServices/);
  }
  assert.match(order, /handleCreateOrder/);
  assert.match(order, /create_order/);
  assert.match(confirm, /handleConfirmPayment/);
  assert.match(confirm, /finalize_payment/);
  assert.match(confirm, /confirmPaymentWithToss/);
  assert.match(confirm, /TOSS_TEST_SECRET_KEY/);
});

Deno.test("결제 함수에서도 JWT 검증을 유지한다", () => {
  const config = Deno.readTextFileSync(new URL("config.toml", supabase));
  assert.match(config, /\[functions\.create-toss-order\][\s\S]*?verify_jwt\s*=\s*true/);
  assert.match(config, /\[functions\.confirm-toss-payment\][\s\S]*?verify_jwt\s*=\s*true/);
  assert.doesNotMatch(config, /verify_jwt\s*=\s*false/);
});
