-- MVP support/bug report schema. No LLM credentials or user message bodies in DB logs.
-- Actual RLS, atomic rate-limit and team handling require Cloud integration tests.

create table public.support_threads (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('question', 'bug')),
  status text not null default 'needs_human' check (status in ('ai_answered', 'needs_human', 'in_progress', 'closed')),
  created_at timestamptz not null default now()
);
create index support_threads_user_created_idx on public.support_threads (user_id, created_at desc);

create table public.support_messages (
  id bigint generated always as identity primary key,
  thread_id uuid not null references public.support_threads(id) on delete cascade,
  role text not null check (role in ('user', 'assistant', 'team')),
  content text not null check (char_length(content) between 1 and 2000),
  created_at timestamptz not null default now()
);

create table public.bug_context (
  thread_id uuid primary key references public.support_threads(id) on delete cascade,
  app_version text,
  platform text,
  device_model text,
  os_version text,
  last_run jsonb not null default '{}'::jsonb check (jsonb_typeof(last_run) = 'object')
);

create table public.chat_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null,
  count integer not null check (count >= 0 and count <= 30),
  primary key (user_id, day)
);

alter table public.support_threads enable row level security;
alter table public.support_messages enable row level security;
alter table public.bug_context enable row level security;
alter table public.chat_usage enable row level security;
revoke all on public.support_threads, public.support_messages, public.bug_context, public.chat_usage from public, anon, authenticated;
grant select on public.support_threads, public.support_messages, public.bug_context, public.chat_usage to authenticated;

create policy support_threads_owner_read on public.support_threads for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));
create policy support_messages_owner_read on public.support_messages for select to authenticated
  using (exists (select 1 from public.support_threads t where t.id = thread_id
    and (t.user_id = (select auth.uid()) or (select public.is_admin()))));
create policy bug_context_owner_read on public.bug_context for select to authenticated
  using (exists (select 1 from public.support_threads t where t.id = thread_id
    and (t.user_id = (select auth.uid()) or (select public.is_admin()))));
create policy chat_usage_owner_read on public.chat_usage for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));

-- Return a non-sensitive sentinel when the daily quota is exhausted.
-- One function call is one Postgres transaction: no quota charge without a stored thread.
create or replace function public.create_support_request(
  p_user_id uuid, p_kind text, p_message text, p_context jsonb
) returns text language plpgsql security definer set search_path = '' as $$
declare
  used integer;
  saved_id uuid;
  utc_day date := (now() at time zone 'UTC')::date;
begin
  if p_user_id is null or p_kind not in ('question', 'bug')
     or p_message is null or char_length(trim(p_message)) not between 1 and 2000
     or (p_kind = 'bug' and p_context is not null and jsonb_typeof(p_context) <> 'object')
     or (p_kind = 'question' and p_context is not null) then
    raise exception 'invalid support request';
  end if;
  insert into public.chat_usage (user_id, day, count)
  values (p_user_id, utc_day, 1)
  on conflict (user_id, day) do update set count = public.chat_usage.count + 1
    where public.chat_usage.count < 30
  returning count into used;
  if used is null then return 'daily_limit_reached'; end if;

  insert into public.support_threads (user_id, kind, status)
  values (p_user_id, p_kind, 'needs_human') returning id into saved_id;
  insert into public.support_messages (thread_id, role, content)
  values (saved_id, 'user', trim(p_message));
  if p_kind = 'bug' then
    insert into public.bug_context (thread_id, app_version, platform, device_model, os_version, last_run)
    values (saved_id, p_context ->> 'app_version', p_context ->> 'platform',
      p_context ->> 'device_model', p_context ->> 'os_version',
      coalesce(p_context -> 'last_run', '{}'::jsonb));
  end if;
  return saved_id::text;
end;
$$;
revoke all on function public.create_support_request(uuid, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.create_support_request(uuid, text, text, jsonb) to service_role;

create or replace function public.finish_support_request(
  p_user_id uuid, p_thread_id uuid, p_status text, p_reply text
) returns text language plpgsql security definer set search_path = '' as $$
declare
  owner_id uuid;
begin
  if p_status not in ('ai_answered', 'needs_human') or p_reply is null
     or char_length(trim(p_reply)) not between 1 and 2000 then
    raise exception 'invalid support result';
  end if;
  select user_id into owner_id from public.support_threads
    where id = p_thread_id for update;
  if not found or owner_id <> p_user_id then raise exception 'thread not found'; end if;
  insert into public.support_messages (thread_id, role, content)
  values (p_thread_id, 'assistant', trim(p_reply));
  update public.support_threads set status = p_status where id = p_thread_id;
  return 'ok';
end;
$$;
revoke all on function public.finish_support_request(uuid, uuid, text, text) from public, anon, authenticated;
grant execute on function public.finish_support_request(uuid, uuid, text, text) to service_role;
