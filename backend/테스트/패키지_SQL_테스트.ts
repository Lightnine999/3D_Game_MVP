import assert from "node:assert/strict";
// Applied migration is immutable historical revision 1, not today's catalog.
const historicalRecipes: Record<string, Record<string, number>> = {
  pack_survival_kit: { spare_knife: 1, ammo_start_pack: 1, supply_flare: 1 },
  pack_one_more: { revive: 2, frenzy_30s: 1, campfire: 1 },
  pack_legend: { revive: 3, spare_knife: 2, frenzy_30s: 2, danger_sense: 2, golden_pistol_skin: 1, supporter_badge: 1 },
};

const migration = new URL("../supabase/migrations/20261001041335_패키지_상품_지급.sql", import.meta.url);
function sql(): string {
  let source = "";
  try { source = Deno.readTextFileSync(migration); } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  }
  assert.ok(source, "패키지 신규 마이그레이션이 필요하다");
  return source.replace(/--[^\n]*/g, "");
}

Deno.test("SQL 구조: 신규 주문은 세 패키지만 허용하고 기존 단품 행은 보존한다", () => {
  const source = sql();
  assert.match(source, /drop constraint toss_orders_product_id_check/i);
  const constraint = source.match(/add constraint toss_orders_product_id_check check \(product_id in \(([\s\S]*?)\)\)/i);
  assert.ok(constraint);
  assert.deepEqual([...constraint[1].matchAll(/'([^']+)'/g)].map((m) => m[1]).sort(),
    ["ammo_start_pack", "supporter_badge", "pack_survival_kit", "pack_one_more", "pack_legend"].sort());
  const create = source.split(/create or replace function public\.create_order/i)[1].split("$$;")[0];
  const prices = Object.fromEntries([...create.matchAll(/when '([^']+)' then (\d+)/g)].map((m) => [m[1], Number(m[2])]));
  assert.deepEqual(prices, { pack_survival_kit: 1100, pack_one_more: 3300, pack_legend: 5500 });
  assert.match(create, /p_amount is distinct from expected_amount/i);
  assert.doesNotMatch(source, /delete from|truncate|drop table|disable row level security|drop policy/i);
});

Deno.test("SQL 구조: 과거 v1 지급 레시피는 원래 세 패키지와 같고 단품은 하나만 지급한다", () => {
  const source = sql();
  const recipeCase = source.match(/recipe := case saved\.product_id([\s\S]*?)end;/i);
  assert.ok(recipeCase);
  const recipes = Object.fromEntries([...recipeCase[1].matchAll(/when '([^']+)' then '([^']+)'::jsonb/g)].map((m) => [m[1], JSON.parse(m[2])]));
  assert.deepEqual(Object.keys(recipes).sort(), ["pack_survival_kit", "pack_one_more", "pack_legend", "ammo_start_pack", "supporter_badge"].sort());
  for (const id of ["pack_survival_kit", "pack_one_more", "pack_legend"]) {
    assert.deepEqual(recipes[id], historicalRecipes[id]);
  }
  assert.deepEqual(recipes.ammo_start_pack, { ammo_start_pack: 1 });
  assert.deepEqual(recipes.supporter_badge, { supporter_badge: 1 });
  assert.match(source, /else null\s+end;\s+if recipe is null then/i);
});

Deno.test("SQL 구조: 잠금·NULL 안전 검증·멱등 반환 후 단일 거래에서 구성품을 순서대로 지급한다", () => {
  const source = sql();
  const finalize = source.split(/create or replace function public\.finalize_payment/i)[1].split("$$;")[0];
  assert.match(finalize, /where order_id = p_order_id for update/i);
  assert.match(finalize, /saved\.user_id is distinct from p_user_id/i);
  assert.match(finalize, /saved\.amount is distinct from p_amount/i);
  assert.match(finalize, /p_payment_key is null or btrim\(p_payment_key\) = ''/i);
  assert.match(finalize, /prior_key is distinct from p_payment_key then\s+raise exception/i);
  assert.match(finalize, /saved\.status is distinct from 'ready'/i);
  assert.ok(finalize.indexOf("return 'already_paid'") < finalize.indexOf("insert into public.purchases"));
  assert.match(finalize, /for component in\s+select key as item_id, value::integer as quantity\s+from jsonb_each_text\(recipe\)\s+order by key collate "C"/i);
  assert.match(finalize, /values \(p_user_id, component\.item_id, component\.quantity\)/i);
  assert.match(finalize, /when excluded\.item_id in \('golden_pistol_skin', 'supporter_badge'\) then 1/i);
  assert.match(finalize, /else public\.inventory\.quantity \+ excluded\.quantity/i);
  assert.ok(finalize.indexOf("insert into public.purchases") < finalize.indexOf("insert into public.inventory"));
  assert.ok(finalize.indexOf("end loop;") < finalize.indexOf("update public.toss_orders set status = 'paid'"));
  assert.doesNotMatch(finalize, /exception when|\bcommit\b|\brollback\b/i);
  for (const signature of ["create_order(uuid, text, text, integer)", "finalize_payment(text, uuid, text, integer)"]) {
    assert.ok(source.includes(`revoke all on function public.${signature} from public, anon, authenticated;`));
    assert.ok(source.includes(`grant execute on function public.${signature} to service_role;`));
  }
  assert.equal((source.match(/security definer set search_path = ''/g) ?? []).length, 2);
  assert.doesNotMatch(source, /grant execute[^;]*to (?:public|anon|authenticated)/i);
});
