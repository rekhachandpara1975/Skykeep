-- PART B — plans, UPI intent payments, free plans, visibility, audit
create table public.plans (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[a-z0-9_-]{2,40}$'),
  name text not null check (length(name) between 1 and 80),
  price_inr integer not null check (price_inr >= 1),
  duration_days integer not null check (duration_days between 1 and 3660),
  perks text[] not null default '{}',
  badge text,
  position integer not null default 0,
  active boolean not null default true,
  free_eligible boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.plans enable row level security;
create policy plans_read on public.plans for select to anon, authenticated using (active or public.is_admin());
create policy plans_owner_insert on public.plans for insert to authenticated with check (public.is_owner());
create policy plans_owner_update on public.plans for update to authenticated
  using (public.is_owner()) with check (public.is_owner());
revoke delete on public.plans from anon, authenticated;

create or replace function private.plans_guard() returns trigger
language plpgsql as $$
begin
  if tg_op = 'DELETE' then raise exception 'plans cannot be deleted; deactivate instead'; end if;
  if new.code <> old.code then raise exception 'plan code is read-only'; end if;
  new.updated_at := now();
  return new;
end $$;
create trigger plans_guard before update or delete on public.plans
  for each row execute function private.plans_guard();

alter table public.subscriptions
  add constraint subscriptions_plan_fk foreign key (plan_id) references public.plans(id);

create table public.plan_catalog (
  id boolean primary key default true check (id),
  revision bigint not null default 1,
  updated_at timestamptz not null default now()
);
insert into public.plan_catalog default values;
alter table public.plan_catalog enable row level security;
create policy plan_catalog_read on public.plan_catalog for select to anon, authenticated using (true);

create or replace function private.bump_catalog() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update public.plan_catalog set revision = revision + 1, updated_at = now();
  return null;
end $$;

-- ---------- payment settings (owner only) ----------
create table public.payment_settings (
  id boolean primary key default true check (id),
  upi_id text check (upi_id is null or upi_id ~ '^[A-Za-z0-9._-]{2,255}@[A-Za-z][A-Za-z0-9]{1,63}$'),
  payee_name text check (payee_name is null or length(payee_name) between 1 and 100),
  enabled boolean not null default true,
  activation_mode text not null default 'instant' check (activation_mode in ('instant','manual')),
  updated_at timestamptz not null default now()
);
insert into public.payment_settings default values;
alter table public.payment_settings enable row level security;
create policy ps_owner_read on public.payment_settings for select to authenticated using (public.is_owner());
create policy ps_owner_update on public.payment_settings for update to authenticated
  using (public.is_owner()) with check (public.is_owner());

create or replace function private.payment_settings_clean() returns trigger
language plpgsql as $$
begin
  new.upi_id := nullif(trim(new.upi_id), '');
  new.payee_name := nullif(trim(new.payee_name), '');
  new.updated_at := now();
  return new;
end $$;
create trigger payment_settings_clean before update on public.payment_settings
  for each row execute function private.payment_settings_clean();

create trigger plans_bump after insert or update on public.plans for each statement execute function private.bump_catalog();
create trigger ps_bump after update on public.payment_settings for each statement execute function private.bump_catalog();
create trigger mode_bump after update on public.app_mode for each statement execute function private.bump_catalog();

create or replace function public.payments_available() returns boolean
language sql stable security definer set search_path = '' as $$
  select not public.free_mode() and exists (select 1 from public.payment_settings
    where enabled and upi_id is not null and payee_name is not null)
$$;

create or replace function public.plans_visible_for_me(uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = '' as $$
  select not public.free_mode() and (public.is_admin(uid) or
    case (select plans_visible_for from public.app_mode limit 1)
      when 'everyone' then true when 'none' then false
      else (select plans_visible_for from public.app_mode limit 1) = public.source_of(uid) end)
$$;

create or replace function public.plan_is_free_for_me(p_plan_id uuid, uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.plans_visible_for_me(uid) and exists (
    select 1 from public.plans p, public.app_mode m
    where p.id = p_plan_id and p.active and p.free_eligible and m.free_plans_for <> 'none'
      and (m.free_plans_for = 'everyone' or m.free_plans_for = public.source_of(uid)))
$$;

-- ---------- orders ----------
create table public.payment_orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  plan_id uuid not null references public.plans(id),
  amount_paise integer not null,
  duration_days integer not null,
  reference text not null unique,
  upi_id_used text,
  payee_used text,
  status text not null default 'pending'
    check (status in ('pending','submitted','review','paid','failed','cancelled','rejected','revoked')),
  raw_response text,
  txn_id text,
  approval_ref text,
  utr text,
  reported_success boolean not null default false,
  auto_activated boolean not null default false,
  bank_verified boolean not null default false,
  bank_verified_at timestamptz,
  paid_at timestamptz,
  admin_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on public.payment_orders (user_id, created_at desc);
create index on public.payment_orders (status, created_at desc);
alter table public.payment_orders enable row level security;
create policy po_read on public.payment_orders for select to authenticated
  using (user_id = auth.uid() or public.is_owner());
alter table public.subscriptions
  add constraint subscriptions_order_fk foreign key (order_id) references public.payment_orders(id);

create table public.payment_reports (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.payment_orders(id) on delete cascade,
  raw text,
  created_at timestamptz not null default now()
);
alter table public.payment_reports enable row level security;
create policy pr_owner on public.payment_reports for select to authenticated using (public.is_owner());

create table private.used_payment_utrs (
  txn_id text primary key,
  order_id uuid not null,
  created_at timestamptz not null default now()
);

-- snapshot price/duration/UPI + random reference from the live rows
create or replace function private.orders_snapshot() returns trigger
language plpgsql security definer set search_path = '' as $$
declare p public.plans; s public.payment_settings;
begin
  select * into p from public.plans where id = new.plan_id;
  select * into s from public.payment_settings limit 1;
  new.amount_paise := p.price_inr * 100;
  new.duration_days := p.duration_days;
  new.upi_id_used := s.upi_id;
  new.payee_used := s.payee_name;
  new.reference := 'SK' || to_char(now() at time zone 'Asia/Kolkata', 'YYYYMMDD')
                   || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  new.status := 'pending';
  return new;
end $$;
create trigger orders_snapshot before insert on public.payment_orders
  for each row execute function private.orders_snapshot();

create or replace function private.order_json(o public.payment_orders) returns jsonb
language sql stable as $$
  select jsonb_build_object('order_id', o.id, 'reference', o.reference, 'plan_id', o.plan_id,
    'amount_paise', o.amount_paise, 'amount_inr', round(o.amount_paise / 100.0, 2),
    'upi_id', o.upi_id_used, 'payee_name', o.payee_used, 'status', o.status, 'created_at', o.created_at)
$$;

create or replace function public.create_order(p_plan_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  p public.plans; s public.payment_settings; o public.payment_orders;
begin
  if not public.is_member(v_uid) then raise exception 'login required' using errcode = '42501'; end if;
  if public.free_mode() then raise exception 'payments are off in free mode'; end if;
  if not public.plans_visible_for_me(v_uid) then raise exception 'plans not available'; end if;
  select * into p from public.plans where id = p_plan_id and active;
  if not found then raise exception 'plan not available'; end if;
  if public.plan_is_free_for_me(p_plan_id, v_uid) then raise exception 'plan is free for you; claim it instead'; end if;
  if not public.payments_available() then raise exception 'payments unavailable'; end if;
  select * into s from public.payment_settings limit 1;

  update public.payment_orders set status = 'cancelled', updated_at = now()
  where user_id = v_uid and status = 'pending' and not reported_success
    and (created_at < now() - interval '2 hours' or plan_id <> p_plan_id
         or amount_paise <> p.price_inr * 100 or upi_id_used is distinct from s.upi_id
         or payee_used is distinct from s.payee_name or duration_days <> p.duration_days);

  -- reuse the fresh matching pending order (double tap)
  select * into o from public.payment_orders
  where user_id = v_uid and status = 'pending' and plan_id = p_plan_id and not reported_success
    and created_at >= now() - interval '2 hours'
  order by created_at desc limit 1;
  if not found then
    insert into public.payment_orders (user_id, plan_id, amount_paise, duration_days, reference)
    values (v_uid, p_plan_id, 0, 0, 'tmp') returning * into o;
  end if;
  return private.order_json(o);
end $$;

create or replace function private.activate_subscription(p_order_id uuid) returns public.subscriptions
language plpgsql security definer set search_path = '' as $$
declare o public.payment_orders; sub public.subscriptions; v_base timestamptz;
begin
  select * into sub from public.subscriptions where order_id = p_order_id;
  if found then return sub; end if;                                  -- idempotent
  select * into o from public.payment_orders where id = p_order_id for update;
  select greatest(now(), coalesce(max(ends_at), now())) into v_base
    from public.subscriptions where user_id = o.user_id and status = 'active';
  insert into public.subscriptions (user_id, plan_id, order_id, kind, ends_at)
  values (o.user_id, o.plan_id, o.id, 'paid', v_base + make_interval(days => o.duration_days))
  returning * into sub;
  update public.payment_orders set status = 'paid', paid_at = now(), updated_at = now() where id = o.id;
  perform private.flag_organic_pending(o.user_id);
  return sub;
end $$;

create or replace function private.flag_organic_pending(uid uuid) returns void
language sql security definer set search_path = '' as $$
  update public.profiles set ads_access_status = 'pending'
  where id = uid and public.source_of(uid) = 'organic' and ads_access_status in ('none','rejected')
$$;

create or replace function private.upi_param(raw text, key text) returns text
language sql immutable as $$
  select nullif(trim((regexp_match(coalesce(raw,''), '(?:^|[&?\s])' || key || '=([^&]*)', 'i'))[1]), '')
$$;

create or replace function public.report_result(p_order_id uuid, p_raw text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  o public.payment_orders; s public.payment_settings;
  v_status text; v_txn text; v_ref text; v_appr text; v_auto int;
begin
  select * into o from public.payment_orders where id = p_order_id and user_id = auth.uid() for update;
  if not found then raise exception 'order not found'; end if;

  -- save raw FIRST
  insert into public.payment_reports (order_id, raw) values (o.id, left(p_raw, 4000));
  update public.payment_orders set raw_response = left(p_raw, 4000), updated_at = now() where id = o.id;

  if o.status not in ('pending','submitted') then
    return jsonb_build_object('status', o.status, 'reference', o.reference);
  end if;

  v_status := upper(coalesce(private.upi_param(p_raw, 'Status'), ''));
  v_txn := private.upi_param(p_raw, 'txnId');
  v_appr := private.upi_param(p_raw, 'ApprovalRefNo');
  v_ref := private.upi_param(p_raw, 'txnRef');

  if v_status in ('FAILURE','FAILED') then
    update public.payment_orders set status = 'failed', txn_id = v_txn, approval_ref = v_appr, updated_at = now() where id = o.id;
    return jsonb_build_object('status', 'failed', 'reference', o.reference);
  end if;

  if v_status = 'SUCCESS' then
    update public.payment_orders set reported_success = true, approval_ref = v_appr where id = o.id;
    v_txn := coalesce(v_txn, v_appr);
    if v_ref is distinct from o.reference
       or v_txn is null or v_txn !~ '^[A-Za-z0-9]{6,40}$'
       or exists (select 1 from private.used_payment_utrs where txn_id = upper(v_txn))
       or o.created_at < now() - interval '2 hours' then
      update public.payment_orders set status = 'submitted', updated_at = now() where id = o.id;
      return jsonb_build_object('status', 'pending', 'reference', o.reference);
    end if;
    insert into private.used_payment_utrs (txn_id, order_id) values (upper(v_txn), o.id);
    update public.payment_orders set txn_id = v_txn where id = o.id;
    select * into s from public.payment_settings limit 1;
    select count(*) into v_auto from public.payment_orders
      where user_id = o.user_id and auto_activated and paid_at > now() - interval '24 hours';
    if s.activation_mode = 'manual' or v_auto >= 3 then
      update public.payment_orders set status = 'review', updated_at = now() where id = o.id;
      return jsonb_build_object('status', 'review', 'reference', o.reference);
    end if;
    update public.payment_orders set auto_activated = true where id = o.id;
    perform private.activate_subscription(o.id);
    return jsonb_build_object('status', 'paid', 'reference', o.reference);
  end if;

  return jsonb_build_object('status', 'pending', 'reference', o.reference);
end $$;

create or replace function public.order_status(p_order_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('status', case when status = 'submitted' then 'pending' else status end,
    'reference', reference, 'amount_inr', round(amount_paise/100.0, 2))
  from public.payment_orders where id = p_order_id and user_id = auth.uid()
$$;

-- ---------- free plans ----------
create table public.free_plan_claims (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  plan_id uuid not null references public.plans(id),
  promo_id uuid not null,
  subscription_id uuid references public.subscriptions(id),
  created_at timestamptz not null default now(),
  unique (user_id, plan_id, promo_id)
);
alter table public.free_plan_claims enable row level security;
create policy fpc_owner_read on public.free_plan_claims for select to authenticated using (public.is_owner());

create or replace function public.claim_free_plan(p_plan_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); p public.plans; m public.app_mode; sub public.subscriptions;
begin
  if not public.is_member(v_uid) then raise exception 'login required' using errcode = '42501'; end if;
  if not public.plan_is_free_for_me(p_plan_id, v_uid) then raise exception 'plan is not free for you'; end if;
  if public.has_active_plan(v_uid) then raise exception 'you already have an active plan'; end if;
  select * into p from public.plans where id = p_plan_id;
  select * into m from public.app_mode limit 1;
  if exists (select 1 from public.free_plan_claims where user_id = v_uid and plan_id = p_plan_id and promo_id = m.promo_id) then
    raise exception 'already claimed';
  end if;
  insert into public.subscriptions (user_id, plan_id, kind, promo_id, ends_at)
  values (v_uid, p.id, 'free_promo', m.promo_id, now() + make_interval(days => p.duration_days)) returning * into sub;
  insert into public.free_plan_claims (user_id, plan_id, promo_id, subscription_id) values (v_uid, p.id, m.promo_id, sub.id);
  perform private.flag_organic_pending(v_uid);
  return jsonb_build_object('plan_name', p.name, 'ends_at', sub.ends_at);
end $$;

create or replace function public.plan_offers() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'free_plan_ids', coalesce((select jsonb_agg(p.id) from public.plans p
                       where p.active and public.plan_is_free_for_me(p.id)), '[]'::jsonb),
    'payments_available', public.payments_available(),
    'plans_visible', public.plans_visible_for_me())
$$;

create or replace function public.request_full_access() returns text
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); v text;
begin
  if not public.is_member(v_uid) then raise exception 'login required' using errcode = '42501'; end if;
  if public.source_of(v_uid) <> 'organic' then return 'approved'; end if;
  update public.profiles set ads_access_status = 'pending'
    where id = v_uid and ads_access_status in ('none','rejected') returning ads_access_status into v;
  return coalesce(v, (select ads_access_status from public.profiles where id = v_uid));
end $$;

-- ---------- audit ----------
create table public.settings_audit (
  id bigint generated always as identity primary key,
  table_name text not null,
  row_ref text,
  field text not null,
  old_value text,
  new_value text,
  changed_by uuid,
  changed_at timestamptz not null default now()
);
alter table public.settings_audit enable row level security;
create policy audit_owner_read on public.settings_audit for select to authenticated using (public.is_owner());

create or replace function private.audit_changes() returns trigger
language plpgsql security definer set search_path = '' as $$
declare k text; o jsonb := case when tg_op = 'INSERT' then '{}'::jsonb else to_jsonb(old) end; n jsonb := to_jsonb(new);
begin
  for k in select jsonb_object_keys(n) loop
    if k in ('updated_at','created_at') then continue; end if;
    if (o -> k) is distinct from (n -> k) then
      insert into public.settings_audit (table_name, row_ref, field, old_value, new_value, changed_by)
      values (tg_table_name, coalesce(n ->> 'code', n ->> 'id'), k, o ->> k, n ->> k, auth.uid());
    end if;
  end loop;
  return null;
end $$;
create trigger plans_audit after insert or update on public.plans for each row execute function private.audit_changes();
create trigger ps_audit after update on public.payment_settings for each row execute function private.audit_changes();
create trigger mode_audit after update on public.app_mode for each row execute function private.audit_changes();
