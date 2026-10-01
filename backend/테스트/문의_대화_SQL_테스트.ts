import assert from "node:assert/strict";

const migration = new URL("../supabase/migrations/20260930234109_문의_대화_연결.sql", import.meta.url);

Deno.test("연속 문의 SQL은 스레드 소유권·일일 한도·최근 대화와 서버 전용 실행을 보장한다", async () => {
  const sql = await Deno.readTextFile(migration);
  assert.match(sql, /create or replace function public\.append_support_message/i);
  assert.match(sql, /user_id\s*=\s*p_user_id/i);
  assert.match(sql, /p_kind|kind\s*<>\s*'question'/i);
  assert.match(sql, /chat_usage\.count\s*<\s*30/i);
  assert.match(sql, /create or replace function public\.support_history/i);
  assert.match(sql, /limit\s+8/i);
  assert.match(sql, /active_request_id uuid/i);
  assert.match(sql, /request_expires_at > clock_timestamp\(\)/i);
  assert.match(sql, /interval '2 minutes'/i);
  assert.ok(sql.indexOf("return 'thread_busy'") < sql.indexOf("insert into public.chat_usage"));
  assert.match(sql, /m.id <= t.request_message_id/i);
  assert.match(sql, /active_request_id = p_request_id/i);
  assert.match(sql, /create or replace function public.release_support_request/i);
  assert.match(sql, /revoke all on function public.finish_support_request\(uuid, uuid, text, text\) from service_role/i);
  assert.match(sql, /revoke all on function public\.append_support_message\(uuid, uuid, text, uuid\) from public, anon, authenticated/i);
  assert.match(sql, /grant execute on function public\.support_history\(uuid, uuid, uuid\) to service_role/i);
});

Deno.test("트랜잭션 검증의 일반 질문에는 버그 맥락 대신 SQL NULL을 전달한다", async () => {
  const fixture = await Deno.readTextFile(new URL("../검증/패키지_문의_트랜잭션_검증.sql", import.meta.url));
  assert.ok(/create_support_request\(\s*u,\s*'question',\s*'transaction probe only',\s*null::jsonb,\s*request_a\s*\)/i.test(fixture),
    "일반 질문 p_context는 NULL이어야 기존 DB 검증 계약을 통과한다");
});
