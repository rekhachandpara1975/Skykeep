-- my_status, admin RPCs, Google Play (prepared, OFF), Meta queue, cron, realtime

-- ---------- Google Play (OFF) ----------
create table public.play_settings (
  id boolean primary key default true check (id),
  play_billing_enabled boolean not null default false,
  google_approval_confirmed boolean not null default false,
  updated_at timestamptz not null default now()
);
insert into public.play_settings default values;
alter table public.play_settings enable row level security;
create policy play_read on public.play_settings for select to anon, authenticated using (true);
create policy play_owner_update on public.play_settings for update to authenticated
  using (public.is_owner()) with check (public.is_owner()
    and (not play_billing_enabled or google_approval_confirmed));   -- cannot enable before Google approval
create trigger play_bump after update on public.play_settings for each statement execute function private.bump_catalog();
create trigger play_audit after update on public.play_settings for each row execute function private.audit_changes();

create table private.play_integrity_challenges (
  nonce text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  used boolean not null default false,
  created_at timestamptz not null default now()
);

create or replace function public.play_integrity_challenge() returns text
language plpgsql security definer set search_path = '' as $$
declare v text := replace(gen_random_uuid()::text,'-','') || replace(gen_random_uuid()::text,'-','');
begin
  if not public.is_member() then raise exception 'login required' using errcode = '42501'; end if;
  insert into private.play_integrity_challenges (nonce, user_id) values (v, auth.uid());
  return v;
end $$;

-- called only by the play-verify edge function (service role) after Google confirms the verdict
create or replace function public.enable_play_free_cloud(p_user_id uuid, p_nonce text) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  update private.play_integrity_challenges set used = true
   where nonce = p_nonce and user_id = p_user_id and not used and created_at > now() - interval '10 minutes';
  if not found then return false; end if;
  update public.profiles set play_verified = true where id = p_user_id;
  return true;
end $$;
revoke execute on function public.enable_play_free_cloud(uuid, text) from public, anon, authenticated;

create table public.play_products (
  product_id text primary key,
  plan_id uuid not null references public.plans(id)
);
alter table public.play_products enable row level security;
create policy pp_read on public.play_products for select to authenticated using (true);
create policy pp_owner on public.play_products for all to authenticated using (public.is_owner()) with check (public.is_owner());

create table public.play_purchases (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  product_id text,
  purchase_token text unique,
  external_transaction_token text,
  kind text check (kind in ('google_play','alternative')),
  verified boolean not null default false,
  reported_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.play_purchases enable row level security;
create policy ppu_read on public.play_purchases for select to authenticated using (user_id = auth.uid() or public.is_owner());

-- ---------- Meta conversions queue ----------
create table private.meta_secrets (
  id boolean primary key default true check (id),
  capi_token text
);
insert into private.meta_secrets default values;

create table public.meta_settings (
  id boolean primary key default true check (id),
  pixel_id text check (pixel_id is null or pixel_id ~ '^[0-9]{5,20}$'),
  test_code text,
  enabled boolean not null default false,
  last_success_at timestamptz,
  last_error text,
  updated_at timestamptz not null default now()
);
insert into public.meta_settings default values;
alter table public.meta_settings enable row level security;
create policy ms_public_read on public.meta_settings for select to anon, authenticated using (true);
create policy ms_owner_update on public.meta_settings for update to authenticated
  using (public.is_owner()) with check (public.is_owner());

create or replace function public.set_meta_token(p_token text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_owner() then raise exception 'owner only' using errcode = '42501'; end if;
  update private.meta_secrets set capi_token = nullif(trim(p_token), '');
end $$;
create or replace function public.meta_token_masked() returns text
language sql stable security definer set search_path = '' as $$
  select case when not public.is_owner() then null
              when capi_token is null then null
              else '••••' || right(capi_token, 4) end from private.meta_secrets
$$;

create table public.meta_events (
  id bigint generated always as identity primary key,
  event_name text not null check (event_name in ('Lead','CompleteRegistration','Purchase')),
  event_id text not null unique,
  user_id uuid references auth.users(id) on delete set null,
  order_id uuid,
  value_inr numeric(12,2),
  status text not null default 'queued' check (status in ('queued','sent','failed','skipped')),
  attempts integer not null default 0,
  last_error text,
  created_at timestamptz not null default now(),
  sent_at timestamptz
);
alter table public.meta_events enable row level security;
create policy me_owner_read on public.meta_events for select to authenticated using (public.is_owner());

create or replace function private.enqueue_registration() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if old.is_guest and not new.is_guest then
    insert into public.meta_events (event_name, event_id, user_id)
    values ('CompleteRegistration', 'reg_' || new.id, new.id) on conflict do nothing;
  end if;
  return null;
end $$;
create trigger profiles_registration after update of is_guest on public.profiles
  for each row execute function private.enqueue_registration();

create or replace function private.enqueue_purchase() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.status = 'paid' and old.status <> 'paid' then
    insert into public.meta_events (event_name, event_id, user_id, order_id, value_inr)
    values ('Purchase', 'order_' || new.id, new.user_id, new.id, new.amount_paise / 100.0) on conflict do nothing;
  end if;
  return null;
end $$;
create trigger orders_purchase after update of status on public.payment_orders
  for each row execute function private.enqueue_purchase();

create or replace function private.enqueue_lead() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.source = 'ads' and new.user_id is not null then
    insert into public.meta_events (event_name, event_id, user_id)
    values ('Lead', 'install_' || new.install_id, new.user_id) on conflict do nothing;
  end if;
  return null;
end $$;
create trigger installs_lead after insert on public.installs
  for each row execute function private.enqueue_lead();

-- ---------- my_status ----------
create or replace function public.my_status() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid(); pr public.profiles; sub record; m public.app_mode; ps public.play_settings;
begin
  select * into pr from public.profiles where id = v_uid;
  select * into m from public.app_mode limit 1;
  select * into ps from public.play_settings limit 1;
  select s.ends_at, p.name into sub from public.subscriptions s left join public.plans p on p.id = s.plan_id
   where s.user_id = v_uid and s.status = 'active' and s.ends_at > now() order by s.ends_at desc limit 1;
  return jsonb_build_object(
    'user_id', v_uid,
    'is_guest', not public.is_member(v_uid),
    'is_admin', public.is_admin(v_uid),
    'source', public.source_of(v_uid),
    'has_ads_access', public.has_ads_access(v_uid),
    'is_premium', public.has_full_access(v_uid),
    'has_plan', sub.ends_at is not null,
    'plan_name', sub.name,
    'plan_ends_at', sub.ends_at,
    'used_bytes', coalesce(pr.used_bytes, 0),
    'quota_bytes', public.quota_bytes(v_uid),
    'free_mode', m.free_mode,
    'paid_enabled', not m.free_mode,
    'access_status', coalesce(pr.ads_access_status, 'none'),
    'payments_available', public.payments_available(),
    'free_plans_for', m.free_plans_for,
    'plans_visible', public.plans_visible_for_me(v_uid),
    'play_verified', coalesce(pr.play_verified, false),
    'play_billing_enabled', ps.play_billing_enabled and ps.google_approval_confirmed,
    'display_name', pr.display_name,
    'avatar_url', pr.avatar_url);
end $$;

-- ---------- admin RPCs (owner) ----------
create or replace function private.require_owner() returns void
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_owner() then raise exception 'owner only' using errcode = '42501'; end if;
end $$;

create or replace function public.admin_mark_paid(p_order_id uuid, p_utr text) returns void
language plpgsql security definer set search_path = '' as $$
declare o public.payment_orders;
begin
  perform private.require_owner();
  select * into o from public.payment_orders where id = p_order_id for update;
  if o.status in ('paid','revoked') then raise exception 'order already %', o.status; end if;
  if p_utr !~ '^[0-9]{12}$' then raise exception 'UTR must be 12 digits'; end if;
  insert into private.used_payment_utrs (txn_id, order_id) values (p_utr, o.id);
  update public.payment_orders set utr = p_utr, updated_at = now() where id = o.id;
  perform private.activate_subscription(o.id);
end $$;

create or replace function public.admin_approve_review(p_order_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_owner();
  if not exists (select 1 from public.payment_orders where id = p_order_id and status = 'review') then
    raise exception 'order is not in review'; end if;
  perform private.activate_subscription(p_order_id);
end $$;

create or replace function public.admin_confirm_bank(p_order_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_owner();
  update public.payment_orders set bank_verified = true, bank_verified_at = now(), updated_at = now()
   where id = p_order_id and status = 'paid';
  if not found then raise exception 'only paid orders can be bank verified'; end if;
end $$;

create or replace function public.admin_reject_order(p_order_id uuid, p_note text default null) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_owner();
  update public.payment_orders set status = 'rejected', admin_note = p_note, updated_at = now()
   where id = p_order_id and status in ('pending','submitted','review','failed');
  if not found then raise exception 'order cannot be rejected (use revoke for paid orders)'; end if;
end $$;

create or replace function public.admin_revoke_order(p_order_id uuid, p_note text default null) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_owner();
  update public.payment_orders set status = 'revoked', admin_note = p_note, updated_at = now()
   where id = p_order_id and status = 'paid';
  if not found then raise exception 'only paid orders can be revoked'; end if;
  update public.subscriptions set status = 'revoked', ends_at = least(ends_at, now()) where order_id = p_order_id;
end $$;

create or replace function public.admin_set_access(p_user_id uuid, p_status text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_owner();
  if p_status not in ('none','pending','approved','rejected') then raise exception 'bad status'; end if;
  update public.profiles set ads_access_status = p_status where id = p_user_id;
end $$;

create or replace function public.admin_grant_premium(p_user_id uuid, p_plan_id uuid, p_days integer) returns void
language plpgsql security definer set search_path = '' as $$
declare v_base timestamptz;
begin
  perform private.require_owner();
  if p_days not between 1 and 3660 then raise exception 'bad duration'; end if;
  select greatest(now(), coalesce(max(ends_at), now())) into v_base
    from public.subscriptions where user_id = p_user_id and status = 'active';
  insert into public.subscriptions (user_id, plan_id, kind, ends_at)
  values (p_user_id, p_plan_id, 'grant', v_base + make_interval(days => p_days));
end $$;

create or replace function public.admin_review_channel(p_channel_id uuid, p_approve boolean, p_audience text default 'all')
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_owner();
  if p_audience not in ('all','organic','ads') then raise exception 'bad audience'; end if;
  update public.channels set review_status = case when p_approve then 'approved' else 'rejected' end,
    audience = case when p_approve then p_audience else audience end, updated_at = now()
  where id = p_channel_id;
end $$;

create or replace function public.admin_users(p_search text default null, p_source text default null,
  p_plan text default null, p_guest boolean default null, p_limit int default 100, p_offset int default 0)
returns table (id uuid, email text, display_name text, is_guest boolean, source text, ads_access_status text,
  plan_name text, plan_ends_at timestamptz, used_bytes bigint, created_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform private.require_owner();
  return query
  select p.id, u.email::text, p.display_name, p.is_guest, public.source_of(p.id), p.ads_access_status,
         s.name, s.ends_at, p.used_bytes, p.created_at
  from public.profiles p join auth.users u on u.id = p.id
  left join lateral (select pl.name, su.ends_at from public.subscriptions su left join public.plans pl on pl.id = su.plan_id
     where su.user_id = p.id and su.status = 'active' and su.ends_at > now() order by su.ends_at desc limit 1) s on true
  where (p_search is null or u.email ilike '%' || p_search || '%' or p.display_name ilike '%' || p_search || '%' or p.id::text = p_search)
    and (p_source is null or public.source_of(p.id) = p_source)
    and (p_guest is null or p.is_guest = p_guest)
    and (p_plan is null or (p_plan = 'active' and s.ends_at is not null) or (p_plan = 'none' and s.ends_at is null))
  order by p.created_at desc limit p_limit offset p_offset;
end $$;

create or replace function public.admin_access_requests(p_status text)
returns table (id uuid, email text, display_name text, source text, plan_name text, plan_ends_at timestamptz, created_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform private.require_owner();
  return query select u.id, u.email::text, u.display_name, u.source, u.plan_name, u.plan_ends_at, u.created_at
    from public.admin_users(null, 'organic', null, false, 1000, 0) u where u.ads_access_status = p_status;
end $$;

create or replace function public.admin_stats() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_today timestamptz := date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
        v_month timestamptz := date_trunc('month', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
begin
  if not public.is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  return jsonb_build_object(
    'channel_requests', (select count(*) from public.channels where review_status = 'pending'),
    'organic_waiting', (select count(*) from public.profiles where ads_access_status = 'pending'),
    'review_orders', (select count(*) from public.payment_orders where status in ('review','submitted')),
    'verify_today', (select count(*) from public.payment_orders where status = 'paid' and not bank_verified and paid_at >= v_today),
    'open_requests', (select count(*) from public.support_requests where status = 'open'),
    'ads_installs', (select count(*) from public.installs where source = 'ads'),
    'organic_installs', (select count(*) from public.installs where source = 'organic'),
    'users', (select count(*) from public.profiles),
    'logged_in', (select count(*) from public.profiles where not is_guest),
    'premium_users', (select count(distinct user_id) from public.subscriptions where status = 'active' and ends_at > now()),
    'channels', (select count(*) from public.channels),
    'posts', (select count(*) from public.posts),
    'revenue_today', (select coalesce(sum(amount_paise),0)/100 from public.payment_orders where status = 'paid' and paid_at >= v_today),
    'revenue_month', (select coalesce(sum(amount_paise),0)/100 from public.payment_orders where status = 'paid' and paid_at >= v_month),
    'free_claims', (select count(*) from public.free_plan_claims),
    'by_campaign', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select source, coalesce(utm_campaign, '—') as campaign, count(*) as installs
        from public.installs group by 1, 2 order by 3 desc limit 50) x));
end $$;

create or replace function public.admin_orders(p_filter text default 'all', p_limit int default 200)
returns table (id uuid, created_at timestamptz, user_id uuid, email text, plan_name text, amount_paise int,
  reference text, txn_id text, utr text, upi_id_used text, status text, raw_response text,
  bank_verified boolean, paid_at timestamptz, admin_note text)
language plpgsql stable security definer set search_path = '' as $$
declare v_today timestamptz := date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
begin
  perform private.require_owner();
  return query select o.id, o.created_at, o.user_id, u.email::text, p.name, o.amount_paise, o.reference, o.txn_id, o.utr,
    o.upi_id_used, o.status, o.raw_response, o.bank_verified, o.paid_at, o.admin_note
  from public.payment_orders o left join auth.users u on u.id = o.user_id left join public.plans p on p.id = o.plan_id
  where case p_filter
    when 'all' then true
    when 'verify_today' then o.status = 'paid' and not o.bank_verified and o.paid_at >= v_today
    when 'review' then o.status in ('review','submitted')
    else o.status = p_filter end
  order by o.created_at desc limit p_limit;
end $$;

create or replace function public.admin_sales() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform private.require_owner();
  return jsonb_build_object(
    'per_plan', (select coalesce(jsonb_agg(x), '[]') from (select p.name, count(o.*) as orders, coalesce(sum(o.amount_paise),0)/100 as revenue
        from public.plans p left join public.payment_orders o on o.plan_id = p.id and o.status = 'paid' group by p.name, p.position order by p.position) x),
    'repeat_buyers', (select coalesce(jsonb_agg(x), '[]') from (select u.email, count(*) as orders, sum(o.amount_paise)/100 as total
        from public.payment_orders o join auth.users u on u.id = o.user_id where o.status = 'paid'
        group by u.email having count(*) > 1 order by 2 desc limit 50) x),
    'plan_counts', (select coalesce(jsonb_object_agg(p.id, jsonb_build_object(
        'subscribers', (select count(distinct s.user_id) from public.subscriptions s where s.plan_id = p.id and s.status='active' and s.ends_at > now()),
        'orders', (select count(*) from public.payment_orders o where o.plan_id = p.id))), '{}') from public.plans p));
end $$;

-- ---------- cron: cancel stale pending orders ----------
create extension if not exists pg_cron;
create or replace function private.cancel_stale_orders() returns integer
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  update public.payment_orders set status = 'cancelled', updated_at = now()
   where status = 'pending' and not reported_success and created_at < now() - interval '24 hours';
  get diagnostics n = row_count;
  return n;
end $$;
select cron.schedule('cancel-stale-orders', '15 * * * *', 'select private.cancel_stale_orders()');

-- ---------- realtime ----------
do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.app_mode, public.plans, public.plan_catalog;
  end if;
end $$;

-- ---------- grants hygiene ----------
revoke execute on all functions in schema private from public, anon, authenticated;
revoke execute on function public.admin_mark_paid(uuid,text), public.admin_approve_review(uuid), public.admin_confirm_bank(uuid),
  public.admin_reject_order(uuid,text), public.admin_revoke_order(uuid,text), public.admin_set_access(uuid,text),
  public.admin_grant_premium(uuid,uuid,integer), public.admin_review_channel(uuid,boolean,text), public.admin_users(text,text,text,boolean,int,int),
  public.admin_access_requests(text), public.admin_stats(), public.admin_orders(text,int), public.admin_sales(),
  public.create_order(uuid), public.report_result(uuid,text), public.claim_free_plan(uuid), public.request_full_access(),
  public.play_integrity_challenge(), public.set_meta_token(text), public.record_install(text,text,text,text)
  from public, anon;
