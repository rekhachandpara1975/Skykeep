-- PART C — Google Play billing for the Play build (prepared, OFF until the owner confirms Google approval)
--   * Google Play path: subscription purchase token verified server-side (edge function play-purchase),
--     acknowledged, entitlement until Google's expiry, one subscription row per purchase token.
--   * User Choice Billing UPI path: Google's externalTransactionToken + buyer state stored with a normal
--     UPI order; once paid, reported to Google within 24 h (edge function play-report, cron).

alter table public.play_products
  add column base_plan_id text,
  add column active boolean not null default true,
  add column created_at timestamptz not null default now();

alter table public.play_purchases
  add column order_id uuid references public.payment_orders(id) on delete set null,
  add column subscription_id uuid references public.subscriptions(id) on delete set null,
  add column buyer_state text,
  add column google_order_id text,
  add column subscription_state text,
  add column expiry_time timestamptz,
  add column acknowledged boolean not null default false,
  add column report_attempts integer not null default 0,
  add column report_error text,
  add column updated_at timestamptz not null default now();
create unique index play_purchases_ext_token on public.play_purchases (external_transaction_token)
  where external_transaction_token is not null;

-- Indian states / UTs (ISO 3166-2:IN suffixes) for Google's userTaxAddress.administrativeArea
create or replace function private.valid_in_state(s text) returns boolean
language sql immutable as $$
  select upper(s) = any (array['AN','AP','AR','AS','BR','CH','CT','DD','DL','DN','GA','GJ','HP','HR','JH','JK',
    'KA','KL','LA','LD','MH','ML','MN','MP','MZ','NL','OR','PB','PY','RJ','SK','TG','TN','TR','UP','UT','WB'])
$$;

create or replace function public.play_billing_on() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select play_billing_enabled and google_approval_confirmed from public.play_settings limit 1), false)
$$;

-- obfuscatedAccountId passed to BillingFlowParams: sha256(user id), never the raw id
create or replace function public.play_account_id() returns text
language sql stable security definer set search_path = '' as $$
  select case when auth.uid() is null then null
    else encode(sha256(convert_to(auth.uid()::text, 'UTF8')), 'hex') end
$$;

-- Play build catalog: active plans that have an active Play product (only when billing is on and plans are visible)
create or replace function public.play_catalog() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('plan_id', p.id, 'name', p.name, 'perks', p.perks, 'badge', p.badge,
           'duration_days', p.duration_days, 'product_id', pp.product_id, 'base_plan_id', pp.base_plan_id)
           order by p.position), '[]'::jsonb)
  from public.plans p join public.play_products pp on pp.plan_id = p.id and pp.active
  where p.active and public.play_billing_on() and public.plans_visible_for_me()
$$;

-- User Choice Billing → user picked "Pay with UPI": normal UPI order + Google's token
create or replace function public.create_play_choice_order(p_plan_id uuid, p_external_token text, p_state text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o jsonb; v_product text;
begin
  if not public.play_billing_on() then raise exception 'play billing is off'; end if;
  if coalesce(length(p_external_token), 0) < 10 then raise exception 'missing external transaction token'; end if;
  if not private.valid_in_state(p_state) then raise exception 'choose your state'; end if;
  select product_id into v_product from public.play_products where plan_id = p_plan_id and active limit 1;
  if v_product is null then raise exception 'plan not available on Google Play'; end if;
  o := public.create_order(p_plan_id);        -- every UPI rule (member, mode, visibility, free plan, payments on)
  insert into public.play_purchases (user_id, product_id, external_transaction_token, kind, order_id, buyer_state)
  values (auth.uid(), v_product, p_external_token, 'alternative', (o ->> 'order_id')::uuid, upper(p_state))
  on conflict (external_transaction_token) where external_transaction_token is not null
  do update set order_id = excluded.order_id, buyer_state = excluded.buyer_state, updated_at = now()
  where public.play_purchases.user_id = auth.uid() and public.play_purchases.reported_at is null;
  return o;
end $$;

-- Google Play path: called by play-purchase (service role) after purchases.subscriptionsv2.get verified the token
create or replace function public.play_record_purchase(
  p_user_id uuid, p_product_id text, p_purchase_token text, p_google_order_id text,
  p_state text, p_expiry timestamptz, p_acknowledged boolean
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare pr public.play_purchases; v_plan uuid; v_active boolean; sub public.subscriptions;
begin
  select plan_id into v_plan from public.play_products where product_id = p_product_id;
  if v_plan is null then raise exception 'unknown play product %', p_product_id; end if;
  select * into pr from public.play_purchases where purchase_token = p_purchase_token for update;
  if found and pr.user_id is distinct from p_user_id then raise exception 'purchase belongs to another account'; end if;
  if not found then
    insert into public.play_purchases (user_id, product_id, purchase_token, kind, verified)
    values (p_user_id, p_product_id, p_purchase_token, 'google_play', true) returning * into pr;
  end if;

  v_active := p_state in ('SUBSCRIPTION_STATE_ACTIVE','SUBSCRIPTION_STATE_IN_GRACE_PERIOD','SUBSCRIPTION_STATE_CANCELED')
              and p_expiry > now();
  if pr.subscription_id is null then
    if v_active then
      insert into public.subscriptions (user_id, plan_id, kind, source, ends_at)
      values (p_user_id, v_plan, 'play', 'google_play', p_expiry) returning * into sub;
      perform private.flag_organic_pending(p_user_id);
    end if;
  else
    update public.subscriptions
       set ends_at = case when v_active then p_expiry else least(ends_at, now()) end,
           status = case when p_state = 'SUBSCRIPTION_STATE_REVOKED' then 'revoked' else 'active' end,
           plan_id = v_plan
     where id = pr.subscription_id returning * into sub;
  end if;

  update public.play_purchases set verified = true, google_order_id = p_google_order_id, subscription_state = p_state,
         expiry_time = p_expiry, acknowledged = p_acknowledged, product_id = p_product_id,
         subscription_id = coalesce(sub.id, subscription_id), updated_at = now()
   where id = pr.id;
  return jsonb_build_object('active', v_active, 'ends_at', p_expiry, 'subscription_id', coalesce(sub.id, pr.subscription_id));
end $$;

-- play-report: paid UCB-UPI orders not yet reported to Google
create or replace function public.play_pending_reports(p_limit int default 50)
returns table (id uuid, external_transaction_token text, buyer_state text, amount_paise integer, paid_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select pp.id, pp.external_transaction_token, pp.buyer_state, o.amount_paise, coalesce(o.paid_at, o.updated_at)
  from public.play_purchases pp join public.payment_orders o on o.id = pp.order_id
  where pp.kind = 'alternative' and o.status = 'paid' and pp.reported_at is null and pp.report_attempts < 20
  order by o.paid_at nulls last limit p_limit
$$;

create or replace function public.play_mark_report(p_id uuid, p_ok boolean, p_error text default null) returns void
language sql security definer set search_path = '' as $$
  update public.play_purchases set report_attempts = report_attempts + 1,
    reported_at = case when p_ok then now() end, report_error = case when p_ok then null else left(p_error, 1000) end,
    updated_at = now()
  where id = p_id
$$;

-- admin: Play status card
create or replace function public.admin_play_overview() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform private.require_owner();
  return jsonb_build_object(
    'products', (select count(*) from public.play_products where active),
    'google_purchases', (select count(*) from public.play_purchases where kind = 'google_play' and verified),
    'upi_choice_orders', (select count(*) from public.play_purchases where kind = 'alternative'),
    'reports_waiting', (select count(*) from public.play_pending_reports(1000)),
    'reports_overdue', (select count(*) from public.play_pending_reports(1000) r where r.paid_at < now() - interval '20 hours'),
    'last_report_error', (select report_error from public.play_purchases where report_error is not null order by updated_at desc limit 1));
end $$;

revoke execute on all functions in schema private from public, anon, authenticated;
revoke execute on function public.play_record_purchase(uuid,text,text,text,text,timestamptz,boolean),
  public.play_pending_reports(int), public.play_mark_report(uuid,boolean,text) from public, anon, authenticated;
grant execute on function public.play_record_purchase(uuid,text,text,text,text,timestamptz,boolean),
  public.play_pending_reports(int), public.play_mark_report(uuid,boolean,text) to service_role;
