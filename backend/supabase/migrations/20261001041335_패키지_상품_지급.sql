-- Additive upgrade: preserve legacy order/purchase/inventory IDs and existing RLS/FKs.
-- New sales are packages only. Legacy ready orders still settle their original single item.
alter table public.toss_orders drop constraint toss_orders_product_id_check;
alter table public.toss_orders add constraint toss_orders_product_id_check check (product_id in (
  'ammo_start_pack', 'supporter_badge',
  'pack_survival_kit', 'pack_one_more', 'pack_legend'
));

create or replace function public.create_order(
  p_user_id uuid, p_order_id text, p_product_id text, p_amount integer
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  expected_amount integer;
  saved public.toss_orders%rowtype;
begin
  expected_amount := case p_product_id
    when 'pack_survival_kit' then 1100
    when 'pack_one_more' then 3300
    when 'pack_legend' then 5500
    else null
  end;
  if p_user_id is null or p_order_id is null or p_order_id !~ '^[A-Za-z0-9_-]{6,64}$'
     or expected_amount is null or p_amount is distinct from expected_amount then
    raise exception 'invalid order or amount';
  end if;
  insert into public.toss_orders (order_id, user_id, product_id, amount, status)
  values (p_order_id, p_user_id, p_product_id, expected_amount, 'ready')
  returning * into saved;
  return jsonb_build_object(
    'order_id', saved.order_id, 'user_id', saved.user_id,
    'product_id', saved.product_id, 'amount', saved.amount, 'status', saved.status
  );
end;
$$;
revoke all on function public.create_order(uuid, text, text, integer) from public, anon, authenticated;
grant execute on function public.create_order(uuid, text, text, integer) to service_role;

-- The server must verify the provider's orderId/paymentKey/totalAmount before this RPC.
-- No client-supplied recipe; all grants and paid status commit or roll back together.
create or replace function public.finalize_payment(
  p_order_id text, p_user_id uuid, p_payment_key text, p_amount integer
) returns text language plpgsql security definer set search_path = '' as $$
declare
  saved public.toss_orders%rowtype;
  prior_key text;
  recipe jsonb;
  component record;
begin
  select * into saved from public.toss_orders where order_id = p_order_id for update;
  if not found or saved.user_id is distinct from p_user_id then
    raise exception 'order not found';
  end if;
  if saved.amount is distinct from p_amount then
    raise exception 'amount mismatch';
  end if;
  if p_payment_key is null or btrim(p_payment_key) = '' then
    raise exception 'invalid payment key';
  end if;
  if saved.status = 'paid' then
    select payment_key into prior_key from public.purchases where order_id = p_order_id;
    if prior_key is distinct from p_payment_key then
      raise exception 'order already paid';
    end if;
    return 'already_paid';
  end if;
  if saved.status is distinct from 'ready' then
    raise exception 'invalid order state';
  end if;

  -- Versioned with the TS catalog; parity is checked by offline SQL structure tests.
  recipe := case saved.product_id
    when 'pack_survival_kit' then '{"spare_knife":1,"ammo_start_pack":1,"supply_flare":1}'::jsonb
    when 'pack_one_more' then '{"revive":2,"frenzy_30s":1,"campfire":1}'::jsonb
    when 'pack_legend' then '{"revive":3,"spare_knife":2,"frenzy_30s":2,"danger_sense":2,"golden_pistol_skin":1,"supporter_badge":1}'::jsonb
    when 'ammo_start_pack' then '{"ammo_start_pack":1}'::jsonb
    when 'supporter_badge' then '{"supporter_badge":1}'::jsonb
    else null
  end;
  if recipe is null then
    raise exception 'unknown product';
  end if;

  -- Existing UNIQUE(order_id) and UNIQUE(payment_key) reject reuse across orders.
  insert into public.purchases (user_id, order_id, payment_key, product_id, amount)
  values (p_user_id, p_order_id, p_payment_key, saved.product_id, saved.amount);

  -- All orders take overlapping inventory row locks in the same bytewise item order.
  for component in
    select key as item_id, value::integer as quantity
    from jsonb_each_text(recipe)
    order by key collate "C"
  loop
    insert into public.inventory (user_id, item_id, quantity)
    values (p_user_id, component.item_id, component.quantity)
    on conflict (user_id, item_id) do update set
      quantity = case
        when excluded.item_id in ('golden_pistol_skin', 'supporter_badge') then 1
        else public.inventory.quantity + excluded.quantity
      end,
      updated_at = now();
  end loop;
  update public.toss_orders set status = 'paid' where order_id = p_order_id;
  return 'paid';
end;
$$;
revoke all on function public.finalize_payment(text, uuid, text, integer) from public, anon, authenticated;
grant execute on function public.finalize_payment(text, uuid, text, integer) to service_role;
