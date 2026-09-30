import assert from "node:assert/strict";

const migration = new URL("../supabase/migrations/20260929231955_테스트_결제_기반.sql", import.meta.url);

Deno.test("주문·구매·인벤토리 테이블은 RLS와 지급 중복 제약을 가진다", () => {
  const sql = Deno.readTextFileSync(migration);
  for (const table of ["toss_orders", "purchases", "inventory"]) {
    assert.match(sql, new RegExp(`create table public\\.${table}\\b`, "i"));
    assert.match(sql, new RegExp(`alter table public\\.${table} enable row level security`, "i"));
  }
  assert.match(sql, /payment_key\s+text\s+not null\s+unique/i);
  assert.match(sql, /order_id\s+text\s+not null\s+unique/i);
  assert.match(sql, /revoke all on public\.toss_orders, public\.purchases, public\.inventory from public, anon, authenticated/i);
});

Deno.test("서버 가격 대조·행 잠금·DB 거래로만 지급하고 RPC는 서버 전용이다", () => {
  const sql = Deno.readTextFileSync(migration);
  assert.match(sql, /create (or replace )?function public\.create_order\s*\(/i);
  assert.match(sql, /when 'ammo_start_pack' then 1100/i);
  assert.match(sql, /when 'supporter_badge' then 3300/i);
  assert.match(sql, /create (or replace )?function public\.finalize_payment\s*\(/i);
  assert.match(sql, /for update/i);
  assert.match(sql, /insert into public\.purchases/i);
  assert.match(sql, /insert into public\.inventory/i);
  assert.match(sql, /update public\.toss_orders set status = 'paid'/i);
  assert.match(sql, /revoke all on function public\.finalize_payment\(text, uuid, text, integer\) from public, anon, authenticated/i);
  assert.match(sql, /grant execute on function public\.finalize_payment\(text, uuid, text, integer\) to service_role/i);
});
