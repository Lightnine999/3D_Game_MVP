import assert from "node:assert/strict";

const migration = new URL("../supabase/migrations/20260929235732_관리자_보기_답변.sql", import.meta.url);

Deno.test("관리자 보기 셋은 서버 역할에만 노출되고 회원 이메일은 가린다", () => {
  const sql = Deno.readTextFileSync(migration);
  for (const view of ["admin_members", "admin_purchases", "admin_support"]) {
    assert.match(sql, new RegExp(`create (or replace )?view public\\.${view}\\b`, "i"));
  }
  assert.match(sql, /revoke all on public\.admin_members, public\.admin_purchases, public\.admin_support from public, anon, authenticated/i);
  assert.match(sql, /grant select on public\.admin_members, public\.admin_purchases, public\.admin_support to service_role/i);
  assert.match(sql, /left\(split_part\(u\.email, '@', 1\), 2\)/i);
});

Deno.test("관리자 답변은 DB의 관리자 역할을 확인하고 팀 메시지로 기록한다", () => {
  const sql = Deno.readTextFileSync(migration);
  assert.match(sql, /create (or replace )?function public\.admin_reply\s*\(/i);
  assert.match(sql, /role\s*=\s*'admin'/i);
  assert.match(sql, /insert into public\.support_messages\s*\(/i);
  assert.match(sql, /'team'/i);
  assert.match(sql, /update public\.support_threads set status\s*=\s*p_status/i);
  assert.match(sql, /revoke all on function public\.admin_reply\(uuid, uuid, text, text\) from public, anon, authenticated/i);
  assert.match(sql, /grant execute on function public\.admin_reply\(uuid, uuid, text, text\) to service_role/i);
});

Deno.test("게스트 이메일 연결 뒤 프로필 재확인은 역할을 유지하며 마스킹만 갱신한다", () => {
  const sql = Deno.readTextFileSync(migration);
  assert.match(sql, /alter table public\.profiles add column email_masked text/i);
  assert.match(sql, /create or replace function public\.ensure_profile\s*\(/i);
  assert.match(sql, /on conflict\s*\(id\) do update\s+set is_guest\s*=\s*excluded\.is_guest/i);
  assert.doesNotMatch(sql, /set role\s*=/i);
});
