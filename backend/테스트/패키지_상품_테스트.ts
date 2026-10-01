import assert from "node:assert/strict";

const moduleUrl = new URL("../supabase/functions/_shared/결제.ts", import.meta.url).href;
function post(body: unknown): Request {
  return new Request("https://example.invalid/create-toss-order", {
    method: "POST", body: JSON.stringify(body),
  });
}

Deno.test("패키지 주문은 외부 응답 형식을 유지하고 클라이언트 레시피·주문 ID를 무시한다", async () => {
  const { handleCreateOrder } = await import(new URL("../supabase/functions/create-toss-order/처리.ts", import.meta.url).href);
  for (const [id, product] of Object.entries(expectedPackages)) {
    const saved: Array<Record<string, unknown>> = [];
    const response = await handleCreateOrder(post({ product_id: id, orderId: "attacker", components: { revive: 999 }, recipe: { revive: 999 } }), {
      authenticate: () => "owner",
      insert: (order: Record<string, unknown>) => { saved.push(order); return order; },
    });
    assert.equal(response.status, 201);
    const body = await response.json();
    assert.match(body.orderId, /^[0-9a-f-]{36}$/);
    assert.deepEqual(body, { orderId: saved[0].order_id, productId: id, amount: product.amount, orderName: product.name, status: "ready" });
    assert.equal(saved[0].product_id, id);
    assert.equal(saved[0].user_id, "owner");
    assert.equal("components" in saved[0], false);
    assert.equal("recipe" in saved[0], false);
  }
});

Deno.test("기존 단품의 신규 주문은 저장 전에 거부한다", async () => {
  const { handleCreateOrder } = await import(new URL("../supabase/functions/create-toss-order/처리.ts", import.meta.url).href);
  for (const id of ["ammo_start_pack", "supporter_badge"]) {
    const response = await handleCreateOrder(post({ product_id: id }), {
      authenticate: () => "owner", insert: () => { throw new Error("must not write"); },
    });
    assert.equal(response.status, 400);
    assert.deepEqual(await response.json(), { error: "unknown_product" });
  }
});

Deno.test("저장된 상품 ID가 다르면 정상 주문으로 공개하지 않는다", async () => {
  const { handleCreateOrder } = await import(new URL("../supabase/functions/create-toss-order/처리.ts", import.meta.url).href);
  const response = await handleCreateOrder(post({ product_id: "pack_survival_kit" }), {
    authenticate: () => "owner",
    insert: (order: Record<string, unknown>) => ({ ...order, product_id: "pack_legend" }),
  });
  assert.equal(response.status, 500);
});

const expectedPackages = {
  pack_survival_kit: { amount: 1100, name: "생존 키트", components: { spare_knife: 1, ammo_start_pack: 1, supply_flare: 1 } },
  pack_one_more: { amount: 3300, name: "한 번 더 패키지", components: { revive: 2, frenzy_30s: 1, campfire: 1 } },
  pack_legend: { amount: 5500, name: "전설의 생존자", components: { revive: 3, spare_knife: 2, frenzy_30s: 2, danger_sense: 2, golden_pistol_skin: 1, supporter_badge: 1 } },
};

Deno.test("신규 판매는 서버의 세 패키지 가격·이름·구성만 제공한다", async () => {
  const { priceFor } = await import(moduleUrl);
  for (const [productId, expected] of Object.entries(expectedPackages)) {
    assert.deepEqual(priceFor(productId), { product_id: productId, ...expected });
  }
  for (const id of ["ammo_start_pack", "supporter_badge", "revive", "unknown", "__proto__", "constructor", "toString"]) {
    assert.equal(priceFor(id), null);
  }
});
