-- Explicitly authorized Server 1 deployment verification only.
-- Uses new random, transaction-local Auth fixtures; NEVER an existing user's ID.
-- All changes roll back. No Toss, email, Auth login, or LLM API call is made.
begin;
do $verify$
declare
  u uuid := gen_random_uuid();
  other_user uuid := gen_random_uuid();
  prefix text := 'verify_' || replace(gen_random_uuid()::text, '-', '');
  p record;
  actual jsonb;
  expected jsonb;
  first_result text;
  replay_result text;
  denied boolean;
  request_a uuid := gen_random_uuid();
  request_b uuid := gen_random_uuid();
  probe_thread text;
  busy_result text;
  usage_before integer;
  usage_after integer;
  messages_before integer;
  messages_after integer;
  history jsonb;
begin
  insert into auth.users(id, aud, role, created_at, updated_at, is_anonymous)
  values (u, 'authenticated', 'authenticated', now(), now(), true);
  for p in select * from (values
    ('pack_survival_kit',1100,'{"spare_knife":1,"ammo_start_pack":1,"supply_flare":1}'::jsonb),
    ('pack_one_more',3300,'{"revive":2,"frenzy_30s":1,"campfire":1}'::jsonb),
    ('pack_legend',5500,'{"revive":3,"spare_knife":2,"frenzy_30s":2,"danger_sense":2,"golden_pistol_skin":1,"supporter_badge":1}'::jsonb)
  ) as packages(product_id, amount, components)
  loop
    -- The fixture owner is fresh and private to this transaction.
    delete from public.inventory where user_id=u;
    perform public.create_order(u,prefix||'_'||p.amount::text,p.product_id,p.amount);
    first_result := public.finalize_payment(prefix||'_'||p.amount::text,u,'synthetic_no_toss_'||prefix||p.amount::text,p.amount);
    replay_result := public.finalize_payment(prefix||'_'||p.amount::text,u,'synthetic_no_toss_'||prefix||p.amount::text,p.amount);
    select jsonb_object_agg(item_id,quantity) into actual from public.inventory where user_id=u;
    if first_result <> 'paid' or replay_result <> 'already_paid' or actual is distinct from p.components then
      raise exception 'package components or replay mismatch: %',p.product_id;
    end if;
    denied:=false;
    begin
      perform public.finalize_payment(prefix||'_'||p.amount::text,other_user,'synthetic_no_toss_'||prefix||p.amount::text,p.amount);
    exception when others then denied:=true; end;
    if not denied then raise exception 'cross-owner approval accepted'; end if;
  end loop;
  -- The legend inventory is still present; a second order accumulates consumables only.
  perform public.create_order(u,prefix||'_second','pack_legend',5500);
  perform public.finalize_payment(prefix||'_second',u,'synthetic_no_toss_'||prefix||'_second',5500);
  select jsonb_object_agg(key,case when key in ('golden_pistol_skin','supporter_badge') then 1 else value::integer*2 end)
  into expected from jsonb_each_text('{"revive":3,"spare_knife":2,"frenzy_30s":2,"danger_sense":2,"golden_pistol_skin":1,"supporter_badge":1}'::jsonb);
  select jsonb_object_agg(item_id,quantity) into actual from public.inventory where user_id=u;
  if actual is distinct from expected then raise exception 'permanent cap or consumable accumulation mismatch'; end if;
  denied:=false;
  begin
    perform public.create_order(u,prefix||'_legacy','ammo_start_pack',1100);
  exception when others then denied:=true; end;
  if not denied then raise exception 'new legacy single sale accepted'; end if;
  denied:=false;
  begin
    perform public.create_order(u,prefix||'_tampered','pack_one_more',1);
  exception when others then denied:=true; end;
  if not denied then raise exception 'tampered package price accepted'; end if;
  -- Request fencing, quota-preserving busy rejection, and stale finish protection.
  probe_thread:=public.create_support_request(u,'question','transaction probe only',NULL::jsonb,request_a);
  select count into usage_before from public.chat_usage where user_id=u;
  select count(*) into messages_before from public.support_messages where support_messages.thread_id=probe_thread::uuid;
  busy_result:=public.append_support_message(u,probe_thread::uuid,'must not be stored',request_b);
  select count into usage_after from public.chat_usage where user_id=u;
  select count(*) into messages_after from public.support_messages where support_messages.thread_id=probe_thread::uuid;
  if busy_result <> 'thread_busy' or usage_before <> usage_after or messages_before <> messages_after then
    raise exception 'support busy request changed quota or messages';
  end if;
  history:=public.support_history(u,probe_thread::uuid,request_a);
  if jsonb_array_length(history) <> 1 or history->0->>'role' <> 'user' then raise exception 'request history mismatch'; end if;
  if public.finish_support_request(u,probe_thread::uuid,'ai_answered','not a model call',request_b) <> 'support_request_expired' then
    raise exception 'stale request was accepted';
  end if;
  if public.finish_support_request(u,probe_thread::uuid,'ai_answered','not a model call',request_a) <> 'ok' then
    raise exception 'active request failed';
  end if;
  if public.append_support_message(u,probe_thread::uuid,'valid continuation',request_b) <> probe_thread then
    raise exception 'continuation failed after release';
  end if;
  history:=public.support_history(u,probe_thread::uuid,request_b);
  if jsonb_array_length(history) <> 3 or history->2->>'content' <> 'valid continuation' then
    raise exception 'continuation history mismatch';
  end if;
  perform set_config('app.deployment_probe','DB_ONLY_NO_TOSS_PASS',true);
end;
$verify$;
select current_setting('app.deployment_probe') as verification;
rollback;
