-- Unapplied migration: request-fenced, expiring per-thread ownership across RPCs.
-- No provider call holds a database transaction/row lock open.
alter table public.support_threads
  add column active_request_id uuid,
  add column request_expires_at timestamptz,
  add column request_message_id bigint;

create or replace function public.append_support_message(
  p_user_id uuid, p_thread_id uuid, p_message text, p_request_id uuid
) returns text language plpgsql security definer set search_path = '' as $$
declare
  t public.support_threads%rowtype;
  used integer;
  message_id bigint;
  utc_day date := (now() at time zone 'UTC')::date;
begin
  if p_user_id is null or p_thread_id is null or p_request_id is null or p_message is null
     or char_length(trim(p_message)) not between 1 and 2000 then
    raise exception 'invalid support request';
  end if;
  select * into t from public.support_threads
    where id = p_thread_id and user_id = p_user_id for update;
  if not found or t.kind <> 'question' or t.status = 'closed' then
    return 'thread_not_found';
  end if;
  -- Must precede quota charge and user-message insertion.
  if t.active_request_id is not null and t.request_expires_at > clock_timestamp() then
    return 'thread_busy';
  end if;
  insert into public.chat_usage (user_id, day, count)
  values (p_user_id, utc_day, 1)
  on conflict (user_id, day) do update set count = public.chat_usage.count + 1
    where public.chat_usage.count < 30
  returning count into used;
  if used is null then return 'daily_limit_reached'; end if;
  insert into public.support_messages (thread_id, role, content)
  values (p_thread_id, 'user', trim(p_message)) returning id into message_id;
  update public.support_threads set status = 'needs_human', active_request_id = p_request_id,
    request_expires_at = clock_timestamp() + interval '2 minutes', request_message_id = message_id
    where id = p_thread_id;
  return p_thread_id::text;
end;
$$;
revoke all on function public.append_support_message(uuid, uuid, text, uuid) from public, anon, authenticated;
grant execute on function public.append_support_message(uuid, uuid, text, uuid) to service_role;

-- The original creator remains an owner-only implementation detail. Creation and lease
-- assignment share this transaction: nobody can append between them.
revoke all on function public.create_support_request(uuid, text, text, jsonb) from service_role;
create or replace function public.create_support_request(
  p_user_id uuid, p_kind text, p_message text, p_context jsonb, p_request_id uuid
) returns text language plpgsql security definer set search_path = '' as $$
declare saved text;
begin
  if p_request_id is null then raise exception 'invalid support request'; end if;
  saved := public.create_support_request(p_user_id, p_kind, p_message, p_context);
  if saved = 'daily_limit_reached' then return saved; end if;
  update public.support_threads set active_request_id = p_request_id,
    request_expires_at = clock_timestamp() + interval '2 minutes',
    request_message_id = (select max(id) from public.support_messages where thread_id = saved::uuid)
    where id = saved::uuid;
  return saved;
end;
$$;
revoke all on function public.create_support_request(uuid, text, text, jsonb, uuid) from public, anon, authenticated;
grant execute on function public.create_support_request(uuid, text, text, jsonb, uuid) to service_role;

create or replace function public.support_history(
  p_user_id uuid, p_thread_id uuid, p_request_id uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  t public.support_threads%rowtype;
  turns jsonb;
begin
  select * into t from public.support_threads
    where id = p_thread_id and user_id = p_user_id and kind = 'question' for update;
  if not found or p_request_id is null or t.active_request_id is distinct from p_request_id
     or t.request_expires_at is null or t.request_expires_at <= clock_timestamp() then
    return to_jsonb('support_request_expired'::text);
  end if;
  select coalesce(jsonb_agg(
    jsonb_build_object('role', recent.role, 'content', recent.content) order by recent.id
  ), '[]'::jsonb) into turns
  from (
    select m.id, m.role, m.content from public.support_messages m
    where m.thread_id = p_thread_id and m.id <= t.request_message_id
      and m.role in ('user', 'assistant')
    order by m.id desc limit 8
  ) recent;
  -- UTF-16 character budget is enforced server-side by askModel, retaining newest question.
  return turns;
end;
$$;
revoke all on function public.support_history(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.support_history(uuid, uuid, uuid) to service_role;

-- Disable the unfenced older entry point; do not edit the applied migration.
revoke all on function public.finish_support_request(uuid, uuid, text, text) from service_role;
create or replace function public.finish_support_request(
  p_user_id uuid, p_thread_id uuid, p_status text, p_reply text, p_request_id uuid
) returns text language plpgsql security definer set search_path = '' as $$
declare t public.support_threads%rowtype;
begin
  if p_status is null or p_status not in ('ai_answered', 'needs_human') or p_reply is null
     or char_length(trim(p_reply)) not between 1 and 2000 then
    raise exception 'invalid support result';
  end if;
  select * into t from public.support_threads
    where id = p_thread_id and user_id = p_user_id for update;
  if not found or p_request_id is null or t.active_request_id is distinct from p_request_id
     or t.request_expires_at is null or t.request_expires_at <= clock_timestamp()
     or t.status = 'closed' then
    return 'support_request_expired';
  end if;
  insert into public.support_messages (thread_id, role, content)
  values (p_thread_id, 'assistant', trim(p_reply));
  update public.support_threads set status = p_status,
    active_request_id = null, request_expires_at = null, request_message_id = null
    where id = p_thread_id;
  return 'ok';
end;
$$;
revoke all on function public.finish_support_request(uuid, uuid, text, text, uuid) from public, anon, authenticated;
grant execute on function public.finish_support_request(uuid, uuid, text, text, uuid) to service_role;

create or replace function public.release_support_request(
  p_user_id uuid, p_thread_id uuid, p_request_id uuid
) returns text language plpgsql security definer set search_path = '' as $$
begin
  -- Already finished/stale requests are no-ops; never clear a newer owner's lease/status.
  update public.support_threads set active_request_id = null,
    request_expires_at = null, request_message_id = null
    where id = p_thread_id and user_id = p_user_id and active_request_id = p_request_id;
  return 'ok';
end;
$$;
revoke all on function public.release_support_request(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.release_support_request(uuid, uuid, uuid) to service_role;
