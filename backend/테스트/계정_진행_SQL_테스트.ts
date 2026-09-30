import assert from "node:assert/strict";

const migration = new URL("../supabase/migrations/20260929223244_계정_진행_기반.sql", import.meta.url);

Deno.test("계정·이벤트·미션 테이블과 각 RLS가 존재한다", () => {
  const sql = Deno.readTextFileSync(migration);
  for (const name of ["profiles", "sync_events", "mission_progress"]) {
    assert.match(sql, new RegExp(`create table public\\.${name}\\b`, "i"));
    assert.match(sql, new RegExp(`alter table public\\.${name} enable row level security`, "i"));
  }
  assert.match(sql, /unique\s*\(\s*user_id\s*,\s*client_event_id\s*\)/i);
});

Deno.test("동기화 RPC는 서버 전용이고 중복 이벤트·미션을 한 번만 반영한다", () => {
  const sql = Deno.readTextFileSync(migration);
  assert.match(sql, /create (or replace )?function public\.sync_submit\s*\(/i);
  assert.match(sql, /security definer set search_path\s*=\s*''/i);
  assert.match(sql, /on conflict\s*\(user_id, client_event_id\) do nothing/i);
  assert.match(sql, /revoke all on function public\.sync_submit\(uuid, jsonb\) from public, anon, authenticated/i);
  assert.match(sql, /grant execute on function public\.sync_submit\(uuid, jsonb\) to service_role/i);
  assert.match(sql, /insert into public\.mission_progress/i);
});

Deno.test("프로필 RPC는 게스트 여부만 갱신하고 관리자 역할을 건드리지 않는다", () => {
  const sql = Deno.readTextFileSync(migration);
  assert.match(sql, /create (or replace )?function public\.ensure_profile\s*\(/i);
  assert.match(sql, /on conflict\s*\(id\) do update\s+set is_guest\s*=\s*excluded\.is_guest/i);
  assert.doesNotMatch(sql, /on conflict\s*\(id\) do update\s+set role/i);
  assert.match(sql, /revoke all on function public\.ensure_profile\(uuid, boolean\) from public, anon, authenticated/i);
  assert.match(sql, /grant execute on function public\.ensure_profile\(uuid, boolean\) to service_role/i);
});
