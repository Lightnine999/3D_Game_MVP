-- MVP admin access: views are readable only by the server role or trusted Studio DB owners.
-- A game user's admin role is checked again in the Edge API and admin_reply RPC.

alter table public.profiles add column email_masked text;
alter table public.support_messages add column author_id uuid references auth.users(id) on delete set null;

-- Refresh only the Auth-derived guest flag and a masked email; never reset nickname/role.
create or replace function public.ensure_profile(p_user_id uuid, p_is_guest boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  saved public.profiles%rowtype;
  masked text;
begin
  if p_user_id is null or p_is_guest is null then raise exception 'invalid profile identity'; end if;
  select case when position('@' in u.email) > 0
    then left(split_part(u.email, '@', 1), 2) || '***@' || split_part(u.email, '@', 2)
    else null end into masked
  from auth.users u where u.id = p_user_id;
  insert into public.profiles (id, is_guest, email_masked)
  values (p_user_id, p_is_guest, masked)
  on conflict (id) do update set is_guest = excluded.is_guest,
    email_masked = excluded.email_masked
  returning * into saved;
  return jsonb_build_object(
    'user_id', saved.id, 'nickname', saved.nickname,
    'is_guest', saved.is_guest, 'role', saved.role
  );
end;
$$;
revoke all on function public.ensure_profile(uuid, boolean) from public, anon, authenticated;
grant execute on function public.ensure_profile(uuid, boolean) to service_role;

-- Views created by postgres can bypass underlying RLS. NEVER grant them to app roles.
create or replace view public.admin_members as
select id as user_id, nickname, is_guest, email_masked, created_at from public.profiles;

create or replace view public.admin_purchases as
select p.user_id, p.order_id, p.product_id, p.amount, p.verified_at,
  o.status, sum(p.amount) over (partition by p.product_id) as product_total
from public.purchases p join public.toss_orders o on o.order_id = p.order_id;

create or replace view public.admin_support as
select t.id as thread_id, t.user_id, t.kind, t.status, t.created_at,
  c.app_version, c.device_model, c.os_version, c.last_run
from public.support_threads t left join public.bug_context c on c.thread_id = t.id;

revoke all on public.admin_members, public.admin_purchases, public.admin_support from public, anon, authenticated;
grant select on public.admin_members, public.admin_purchases, public.admin_support to service_role;

create or replace function public.admin_reply(
  p_admin_id uuid, p_thread_id uuid, p_reply text, p_status text
) returns text language plpgsql security definer set search_path = '' as $$
declare
  target_id uuid;
begin
  if p_admin_id is null or not exists (
    select 1 from public.profiles where id = p_admin_id and role = 'admin'
  ) then raise exception 'not admin'; end if;
  if p_status not in ('in_progress', 'closed') or p_reply is null
     or char_length(trim(p_reply)) not between 1 and 2000 then
    raise exception 'invalid admin reply';
  end if;
  select id into target_id from public.support_threads
    where id = p_thread_id for update;
  if not found then raise exception 'thread not found'; end if;
  insert into public.support_messages (thread_id, role, content, author_id)
  values (p_thread_id, 'team', trim(p_reply), p_admin_id);
  update public.support_threads set status = p_status where id = p_thread_id;
  return 'ok';
end;
$$;
revoke all on function public.admin_reply(uuid, uuid, text, text) from public, anon, authenticated;
grant execute on function public.admin_reply(uuid, uuid, text, text) to service_role;
