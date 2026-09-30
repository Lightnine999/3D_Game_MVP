-- MVP test payment schema. Keep test secrets and approval calls in Edge Functions only.
-- Runtime tests against the exact Cloud project are required before marking grants verified.

create table public.toss_orders (
  order_id text primary key check (order_id ~ '^[A-Za-z0-9_-]{6,64}$'),
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id text not null check (product_id in ('ammo_start_pack', 'supporter_badge')),
  amount integer not null check (amount > 0),
  status text not null default 'ready' check (status in ('ready', 'paid', 'failed')),
  created_at timestamptz not null default now()
);
create index toss_orders_user_created_idx on public.toss_orders (user_id, created_at desc);

create table public.purchases (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  order_id text not null unique references public.toss_orders(order_id),
  payment_key text not null unique,
  product_id text not null,
  amount integer not null check (amount > 0),
  verified_at timestamptz not null default now()
);
create index purchases_user_verified_idx on public.purchases (user_id, verified_at desc);

create table public.inventory (
  user_id uuid not null references auth.users(id) on delete cascade,
  item_id text not null,
  quantity integer not null default 0 check (quantity >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, item_id)
);

alter table public.toss_orders enable row level security;
alter table public.purchases enable row level security;
alter table public.inventory enable row level security;
revoke all on public.toss_orders, public.purchases, public.inventory from public, anon, authenticated;
grant select on public.toss_orders, public.purchases, public.inventory to authenticated;

create policy toss_orders_owner_read on public.toss_orders for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));
create policy purchases_owner_read on public.purchases for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));
create policy inventory_owner_read on public.inventory for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));

-- Only the server calls this after choosing the product price; the DB checks it again.
create or replace function public.create_order(
  p_user_id uuid, p_order_id text, p_product_id text, p_amount integer
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  expected_amount integer;
  saved public.toss_orders%rowtype;
begin
  expected_amount := case p_product_id
    when 'ammo_start_pack' then 1100
    when 'supporter_badge' then 3300
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

-- Invoke only after Toss confirms the same orderId/paymentKey/totalAmount.
-- PostgreSQL holds the order row lock and commits purchase, inventory and paid status together.
create or replace function public.finalize_payment(
  p_order_id text, p_user_id uuid, p_payment_key text, p_amount integer
) returns text language plpgsql security definer set search_path = '' as $$
declare
  saved public.toss_orders%rowtype;
  prior_key text;
begin
  select * into saved from public.toss_orders where order_id = p_order_id for update;
  if not found or saved.user_id <> p_user_id then
    raise exception 'order not found';
  end if;
  if saved.amount <> p_amount then
    raise exception 'amount mismatch';
  end if;
  if saved.status = 'paid' then
    select payment_key into prior_key from public.purchases where order_id = p_order_id;
    if prior_key = p_payment_key then return 'already_paid'; end if;
    raise exception 'order already paid';
  end if;
  if saved.status <> 'ready' or p_payment_key is null or p_payment_key = '' then
    raise exception 'invalid order state or payment key';
  end if;
  insert into public.purchases (user_id, order_id, payment_key, product_id, amount)
  values (p_user_id, p_order_id, p_payment_key, saved.product_id, saved.amount);
  insert into public.inventory (user_id, item_id, quantity)
  values (p_user_id, saved.product_id, 1)
  on conflict (user_id, item_id) do update set
    quantity = public.inventory.quantity + excluded.quantity,
    updated_at = now();
  update public.toss_orders set status = 'paid' where order_id = p_order_id;
  return 'paid';
end;
$$;
revoke all on function public.finalize_payment(text, uuid, text, integer) from public, anon, authenticated;
grant execute on function public.finalize_payment(text, uuid, text, integer) to service_role;
