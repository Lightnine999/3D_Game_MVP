-- MVP account and offline progress schema. Deploy only from backend/, never from 01_사전검증/.
-- Runtime test with two isolated users is required before calling these policies verified.

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null default '',
  is_guest boolean not null default true,
  role text not null default 'user' check (role in ('user', 'admin')),
  created_at timestamptz not null default now()
);

create table public.sync_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  client_event_id text not null check (client_event_id ~ '^[A-Za-z0-9_-]{1,80}$'),
  kind text not null check (kind in ('mission', 'distance')),
  payload jsonb not null default '{}'::jsonb
    check (jsonb_typeof(payload) = 'object' and octet_length(payload::text) <= 8192),
  created_at timestamptz not null default now(),
  unique (user_id, client_event_id)
);
create index sync_events_user_created_idx on public.sync_events (user_id, created_at, id);

create table public.mission_progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  stage_id text not null check (stage_id ~ '^[A-Za-z0-9_-]{1,80}$'),
  mission_id text not null check (mission_id ~ '^[A-Za-z0-9_-]{1,80}$'),
  completed_at timestamptz not null default now(),
  primary key (user_id, stage_id, mission_id)
);

alter table public.profiles enable row level security;
alter table public.sync_events enable row level security;
alter table public.mission_progress enable row level security;

revoke all on public.profiles, public.sync_events, public.mission_progress from public, anon, authenticated;
grant select on public.profiles, public.sync_events, public.mission_progress to authenticated;
grant update (nickname) on public.profiles to authenticated;

-- Separate identity verification from the RLS query to avoid recursive profile lookup.
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'admin'
  );
$$;
revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

create policy profile_owner_read on public.profiles for select to authenticated
  using (id = (select auth.uid()) or (select public.is_admin()));
create policy profile_owner_nickname on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));
create policy sync_events_owner_read on public.sync_events for select to authenticated
  using (user_id = (select auth.uid()));
create policy mission_progress_owner_read on public.mission_progress for select to authenticated
  using (user_id = (select auth.uid()));

-- Only an Edge Function with a service role may call this RPC, after auth.getUser().
create or replace function public.sync_submit(p_user_id uuid, p_events jsonb)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  item jsonb;
  event_id text;
  event_kind text;
  event_payload jsonb;
  stage text;
  mission text;
  inserted integer;
  total integer := 0;
begin
  if p_user_id is null or jsonb_typeof(p_events) is distinct from 'array'
     or jsonb_array_length(p_events) < 1 or jsonb_array_length(p_events) > 100 then
    raise exception 'invalid event batch';
  end if;
  for item in select value from jsonb_array_elements(p_events) as e(value) loop
    if jsonb_typeof(item) is distinct from 'object' then
      raise exception 'invalid event';
    end if;
    event_id := item ->> 'id';
    event_kind := item ->> 'kind';
    event_payload := item -> 'payload';
    if event_id is null or event_id !~ '^[A-Za-z0-9_-]{1,80}$'
       or event_kind is null or event_kind not in ('mission', 'distance')
       or jsonb_typeof(event_payload) is distinct from 'object'
       or octet_length(event_payload::text) > 8192 then
      raise exception 'invalid event';
    end if;
    if event_kind = 'mission' then
      stage := event_payload ->> 'stage_id';
      mission := event_payload ->> 'mission_id';
      if stage is null or stage !~ '^[A-Za-z0-9_-]{1,80}$'
         or mission is null or mission !~ '^[A-Za-z0-9_-]{1,80}$' then
        raise exception 'invalid mission';
      end if;
    end if;
    insert into public.sync_events (user_id, client_event_id, kind, payload)
    values (p_user_id, event_id, event_kind, event_payload)
    on conflict (user_id, client_event_id) do nothing;
    get diagnostics inserted = row_count;
    total := total + inserted;
    if inserted > 0 and event_kind = 'mission' then
      insert into public.mission_progress (user_id, stage_id, mission_id)
      values (p_user_id, stage, mission)
      on conflict (user_id, stage_id, mission_id) do nothing;
    end if;
  end loop;
  return total;
end;
$$;
revoke all on function public.sync_submit(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.sync_submit(uuid, jsonb) to service_role;

-- The verified Auth account is the only source for the profile ID/guest flag.
-- Conflict updates deliberately leave nickname and role unchanged.
create or replace function public.ensure_profile(p_user_id uuid, p_is_guest boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  saved public.profiles%rowtype;
begin
  if p_user_id is null or p_is_guest is null then
    raise exception 'invalid profile identity';
  end if;
  insert into public.profiles (id, is_guest)
  values (p_user_id, p_is_guest)
  on conflict (id) do update set is_guest = excluded.is_guest
  returning * into saved;
  return jsonb_build_object(
    'user_id', saved.id,
    'nickname', saved.nickname,
    'is_guest', saved.is_guest,
    'role', saved.role
  );
end;
$$;
revoke all on function public.ensure_profile(uuid, boolean) from public, anon, authenticated;
grant execute on function public.ensure_profile(uuid, boolean) to service_role;
