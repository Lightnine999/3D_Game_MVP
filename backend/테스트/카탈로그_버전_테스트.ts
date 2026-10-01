import assert from "node:assert/strict";
import { confirmOnce, priceFor, type Order } from "../supabase/functions/_shared/결제.ts";
import { handleCreateOrder } from "../supabase/functions/create-toss-order/처리.ts";


Deno.test("승인 전 미지·누락 버전은 차단하고 v1·v2 주문은 저장 버전 그대로 지급기로 전달한다", async () => {
  for (const version of [1, 2, 3, null, undefined]) {
    let calls = 0;
    const order = { order_id: "order_version", user_id: "owner", product_id: "pack_one_more", amount: 3300, status: "ready", catalog_version: version } as Order;
    const result = await confirmOnce(order, "owner", { orderId: order.order_id, paymentKey: "test-key", amount: 3300 }, {
      requestApproval: async () => { calls++; return { orderId: order.order_id, paymentKey: "test-key", totalAmount: 3300, status: "DONE" }; },
      grant: async (stored) => { assert.equal(stored.catalog_version, version); calls++; return "paid"; },
    });
    assert.equal(result, version === 1 || version === 2 ? "paid" : "unknown_catalog_version");
    assert.equal(calls, version === 1 || version === 2 ? 2 : 0);
  }
});

function literal<T>(name: string): Record<string, T> {
  const source = Deno.readTextFileSync(new URL("../../godot/scripts/stage/inventory.gd", import.meta.url));
  const text = source.match(new RegExp(`const ${name} := (\\{[\\s\\S]*?\\n\\})`))?.[1];
  assert.ok(text);
  return JSON.parse(text.replace(/#[^\n]*/g, "").replace(/,\s*}/g, "}"));
}
Deno.test("카탈로그 v2: 팀 Inventory 리터럴의 10종 ID·가격·구성과 정확히 일치한다", () => {
  const items = literal<{ name: string; kind: string }>("ITEMS");
  assert.equal(Object.keys(items).length, 10);
  const ids = new Set<string>();
  for (const [id, pack] of Object.entries(literal<{ price: number; items: Record<string, number> }>("PACKS"))) {
    const actual = priceFor(id);
    assert.equal(actual?.amount, pack.price);
    assert.deepEqual(actual?.components, pack.items);
    for (const item of Object.keys(actual!.components)) {
      assert.ok(Object.hasOwn(items, item));
      ids.add(item);
    }
  }
  assert.deepEqual([...ids].sort(), Object.keys(items).sort());
  assert.equal(items.frenzy_30.name, "광란의 15초");
});
Deno.test("신규 주문은 저장된 catalog_version 2만 catalogVersion 2로 공개한다", async () => {
  for (const version of [2, 1, 3, null, undefined, "2"]) {
    const response = await handleCreateOrder(new Request("https://example.invalid", {
      method: "POST", body: JSON.stringify({ product_id: "pack_one_more", catalogVersion: 1 }),
    }), {
      authenticate: () => "owner",
      insert: (order) => {
        assert.equal(order.catalog_version, 2);
        return { ...order, catalog_version: version } as Order;
      },
    });
    assert.equal(response.status, version === 2 ? 201 : 500);
    if (version === 2) assert.equal((await response.json()).catalogVersion, 2);
  }
});
