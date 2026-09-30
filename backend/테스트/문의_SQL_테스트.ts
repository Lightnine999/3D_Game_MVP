import assert from "node:assert/strict";

const migration = new URL("../supabase/migrations/20260929234951_문의_제보_기반.sql", import.meta.url);

Deno.test("문의 테이블 모두 RLS·사용자 소유 경계를 갖는다", () => {
  const sql = Deno.readTextFileSync(migration);
  for (const table of ["support_threads", "support_messages", "bug_context", "chat_usage"]) {
    assert.match(sql, new RegExp(`create table public\\.${table}\\b`, "i"));
    assert.match(sql, new RegExp(`alter table public\\.${table} enable row level security`, "i"));
  }
  assert.match(sql, /revoke all on public\.support_threads, public\.support_messages, public\.bug_context, public\.chat_usage from public, anon, authenticated/i);
});

Deno.test("하루 제한과 문의 저장·답변 변경은 서버 전용 RPC로 한 DB 거래에 묶인다", () => {
  const sql = Deno.readTextFileSync(migration);
  assert.match(sql, /create (or replace )?function public\.create_support_request\s*\(/i);
  assert.match(sql, /public\.chat_usage\.count\s*<\s*30/i);
  assert.match(sql, /insert into public\.support_threads/i);
  assert.match(sql, /insert into public\.support_messages/i);
  assert.match(sql, /insert into public\.bug_context/i);
  assert.match(sql, /create (or replace )?function public\.finish_support_request\s*\(/i);
  assert.match(sql, /update public\.support_threads set status\s*=\s*p_status/i);
  assert.match(sql, /revoke all on function public\.create_support_request\(uuid, text, text, jsonb\) from public, anon, authenticated/i);
  assert.match(sql, /grant execute on function public\.create_support_request\(uuid, text, text, jsonb\) to service_role/i);
});
