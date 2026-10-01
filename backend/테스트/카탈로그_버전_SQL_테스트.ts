import assert from "node:assert/strict";
import { priceFor } from "../supabase/functions/_shared/결제.ts";
const directory = new URL("../supabase/migrations/", import.meta.url);
function latest(): string {
  const names = [...Deno.readDirSync(directory)].map((e) => e.name).filter((n) => n.endsWith("_카탈로그_버전_보존.sql"));
  assert.equal(names.length, 1, "기존 주문 버전을 보존하는 추가 마이그레이션 필요");
  return Deno.readTextFileSync(new URL(names[0], directory)).replace(/--[^\n]*/g, "");
}
function recipes(source: string): Record<string, unknown> {
  return Object.fromEntries([...source.matchAll(/when '([^']+)' then '([^']+)'::jsonb/g)].map((m) => [m[1], JSON.parse(m[2])]));
}
Deno.test("SQL 구조: 기존 행 기본 버전1·불변 트리거·신규 RPC 버전2", () => {
  const source = latest();
  assert.match(source, /add column catalog_version integer not null default 1/i);
  assert.match(source, /check \(catalog_version in \(1, 2\)\)/i);
  assert.match(source, /new\.catalog_version is distinct from old\.catalog_version/i);
  assert.match(source, /raise exception 'catalog version is immutable'/i);
  assert.match(source, /before update on public\.toss_orders[\s\S]*execute function public\.preserve_order_catalog_version\(\)/i);
  const create = source.split("function public.create_order")[1].split("$$;")[0];
  assert.match(create, /status, catalog_version\)/);
  assert.match(create, /expected_amount, 'ready', 2\)/);
  assert.match(create, /'catalog_version', saved\.catalog_version/);
  assert.match(create, /p_amount is distinct from expected_amount/);
  assert.doesNotMatch(source, /delete from|truncate|drop table|update public\.inventory|set item_id|disable row level security/i);
});
Deno.test("SQL 구조: v1 과거 레시피 원본 보존·v2 팀 구성 일치·미지 버전 차단", () => {
  const source = latest();
  const old = Deno.readTextFileSync(new URL("20261001041335_패키지_상품_지급.sql", directory));
  const branch1 = source.match(/if saved\.catalog_version = 1 then([\s\S]*?)elsif saved\.catalog_version = 2 then/);
  const branch2 = source.match(/elsif saved\.catalog_version = 2 then([\s\S]*?)else\s+raise exception 'unknown catalog version'/);
  assert.ok(branch1); assert.ok(branch2);
  assert.deepEqual(recipes(branch1[1]), recipes(old));
  const v2 = recipes(branch2[1]);
  assert.deepEqual(Object.keys(v2).sort(), ["pack_legend", "pack_one_more", "pack_survival_kit"]);
  for (const [id, recipe] of Object.entries(v2)) assert.deepEqual(recipe, priceFor(id)?.components);
  assert.match(source, /saved\.catalog_version is null or saved\.catalog_version not in \(1, 2\)/);
  assert.ok(source.indexOf("raise exception 'unknown catalog version'") < source.indexOf("return 'already_paid'"));
});
Deno.test("SQL 구조: 버전 분기에도 원자성·결제키 멱등·잠금 순서·신구 영구품 상한 유지", () => {
  const source = latest();
  const finalize = source.split("function public.finalize_payment")[1].split("$$;")[0];
  for (const text of ["for update", "saved.user_id is distinct from p_user_id", "saved.amount is distinct from p_amount", "prior_key is distinct from p_payment_key", "saved.status is distinct from 'ready'", "order by key collate \"C\"", "else public.inventory.quantity + excluded.quantity"]) assert.ok(finalize.includes(text), text);
  assert.match(finalize, /p_payment_key is null or btrim\(p_payment_key\) = ''/);
  assert.match(finalize, /when excluded.item_id in \('golden_pistol_skin', 'gold_pistol', 'supporter_badge'\) then 1/);
  assert.ok(finalize.indexOf("return 'already_paid'") < finalize.indexOf("insert into public.purchases"));
  assert.ok(finalize.indexOf("insert into public.purchases") < finalize.indexOf("insert into public.inventory"));
  assert.ok(finalize.indexOf("end loop;") < finalize.indexOf("update public.toss_orders set status = 'paid'"));
  assert.doesNotMatch(finalize, /exception when|\bcommit\b|\brollback\b/i);
  for (const signature of ["create_order(uuid, text, text, integer)", "finalize_payment(text, uuid, text, integer)"]) {
    assert.ok(source.includes(`revoke all on function public.${signature} from public, anon, authenticated;`));
    assert.ok(source.includes(`grant execute on function public.${signature} to service_role;`));
  }
  const base = Deno.readTextFileSync(new URL("20260929231955_테스트_결제_기반.sql", directory));
  assert.match(base, /order_id text not null unique/); assert.match(base, /payment_key text not null unique/);
});
