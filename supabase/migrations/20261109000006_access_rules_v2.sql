-- PART A (v2) — access rules exactly as docs/rules.md
-- * guests never get "ads" content or full premium
-- * paid mode: an active plan alone unlocks premium items the user can see (approval only gates "ads" content)
-- * free mode: ads members always; organic members only when approved
-- * subscriptions.source (upi_app | admin | google_play | free_promo | provider_api)
-- * helpers that take a user id answer only for yourself (admins / service role may ask about anyone)

-- ---------- defence in depth on private tables (only definer functions touch them) ----------
alter table private.user_sources enable row level security;
alter table private.used_payment_utrs enable row level security;
alter table private.play_integrity_challenges enable row level security;
alter table private.meta_secrets enable row level security;

create or replace function private.uid_ok(uid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select auth.uid() is null                      -- service role, cron, migrations
      or uid is not distinct from auth.uid()
      or exists (select 1 from public.admins a where a.user_id = auth.uid())
$$;

create or replace function public.source_of(uid uuid default auth.uid()) returns text
language sql stable security definer set search_path = '' as $$
  select case when private.uid_ok(uid)
    then coalesce((select s.source from private.user_sources s where s.user_id = uid), 'organic') end
$$;

create or replace function public.has_active_plan(uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.uid_ok(uid) and exists (select 1 from public.subscriptions s
    where s.user_id = uid and s.status = 'active' and s.ends_at > now())
$$;

create or replace function public.has_plan(uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.has_active_plan(uid)
$$;

-- full access ("ads" content): ads members always; organic members when approved AND (free mode OR active plan)
create or replace function public.has_ads_access(uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.uid_ok(uid) and (public.is_admin(uid) or (public.is_member(uid) and (
         public.source_of(uid) = 'ads'
      or (coalesce((select p.ads_access_status from public.profiles p where p.id = uid),'none') = 'approved'
          and (public.free_mode() or public.has_active_plan(uid))))))
$$;

-- premium items in full (and downloads)
--   paid mode: active plan
--   free mode: full access (ads members always, organic members when approved)
create or replace function public.has_full_access(uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.uid_ok(uid) and (public.is_admin(uid) or (public.is_member(uid) and
    case when public.free_mode() then public.has_ads_access(uid) else public.has_active_plan(uid) end))
$$;

create or replace function public.can_see_audience(aud text, uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = '' as $$
  select aud = 'all' or public.is_admin(uid)
      or (aud = 'organic' and uid is not null and public.source_of(uid) = 'organic')
      or (aud = 'ads' and public.has_ads_access(uid))
$$;

create or replace function public.quota_bytes(uid uuid default auth.uid()) returns bigint
language sql stable security definer set search_path = '' as $$
  select case
    when not private.uid_ok(uid) then 0::bigint
    when public.has_active_plan(uid) then 2199023255552::bigint            -- 2 TB
    when public.is_member(uid) and (public.free_mode()
         or coalesce((select play_verified from public.profiles where id = uid), false))
      then 16106127360::bigint                                              -- 15 GB
    else 0::bigint end
$$;

create or replace function public.plans_visible_for_me(uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.uid_ok(uid) and not public.free_mode() and (public.is_admin(uid) or
    case (select plans_visible_for from public.app_mode limit 1)
      when 'everyone' then true when 'none' then false
      else (select plans_visible_for from public.app_mode limit 1) = public.source_of(uid) end)
$$;

create or replace function public.free_plan_for_me(p_plan_id uuid, uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.plan_is_free_for_me(p_plan_id, uid)
$$;

-- can the caller see this post item at all (and what will they get)?
create or replace function public.can_view(p_item_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'visible', i.id is not null and public.post_visible(i.post_id),
    'full', i.id is not null and public.post_visible(i.post_id) and (not i.is_premium or public.has_full_access()),
    'download', i.id is not null and public.post_visible(i.post_id) and public.is_member()
                and (not i.is_premium or public.has_full_access()),
    'trailer', i.id is not null and public.post_visible(i.post_id) and i.is_premium
               and not public.has_full_access() and i.trailer_key is not null)
  from (select 1) x left join public.post_items i on i.id = p_item_id
$$;

-- ---------- subscriptions.source ----------
alter table public.subscriptions drop constraint if exists subscriptions_kind_check;
alter table public.subscriptions add constraint subscriptions_kind_check
  check (kind in ('paid','free_promo','grant','play'));
alter table public.subscriptions add column source text
  check (source in ('upi_app','admin','google_play','free_promo','provider_api'));
update public.subscriptions set source = case kind when 'free_promo' then 'free_promo' when 'grant' then 'admin' else 'upi_app' end;

create or replace function private.subscriptions_source() returns trigger
language plpgsql as $$
begin
  if new.source is null then
    new.source := case new.kind when 'free_promo' then 'free_promo' when 'grant' then 'admin'
                                when 'play' then 'google_play' else 'upi_app' end;
  end if;
  return new;
end $$;
create trigger subscriptions_source before insert on public.subscriptions
  for each row execute function private.subscriptions_source();
alter table public.subscriptions alter column source set not null;

-- activation with an explicit source (admin / provider_api); old 1-arg version kept for upi_app
create or replace function private.activate_subscription(p_order_id uuid, p_source text) returns public.subscriptions
language plpgsql security definer set search_path = '' as $$
declare sub public.subscriptions;
begin
  sub := private.activate_subscription(p_order_id);
  if sub.source <> p_source and sub.created_at > now() - interval '5 seconds' then
    update public.subscriptions set source = p_source where id = sub.id returning * into sub;
  end if;
  return sub;
end $$;

create or replace function public.admin_mark_paid(p_order_id uuid, p_utr text) returns void
language plpgsql security definer set search_path = '' as $$
declare o public.payment_orders;
begin
  perform private.require_owner();
  select * into o from public.payment_orders where id = p_order_id for update;
  if not found then raise exception 'order not found'; end if;
  if o.status in ('paid','revoked') then raise exception 'order already %', o.status; end if;
  if p_utr !~ '^[0-9]{12}$' then raise exception 'UTR must be 12 digits'; end if;
  insert into private.used_payment_utrs (txn_id, order_id) values (p_utr, o.id);
  update public.payment_orders set utr = p_utr, updated_at = now() where id = o.id;
  perform private.activate_subscription(o.id, 'admin');
end $$;

create or replace function public.admin_approve_review(p_order_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_owner();
  if not exists (select 1 from public.payment_orders where id = p_order_id and status = 'review') then
    raise exception 'order is not in review'; end if;
  perform private.activate_subscription(p_order_id, 'admin');
end $$;

create or replace function public.provider_payment_update(p_reference text, p_utr text, p_amount_paise integer)
returns text language plpgsql security definer set search_path = '' as $$
declare o public.payment_orders;
begin
  select * into o from public.payment_orders where reference = p_reference for update;
  if not found then return 'unknown_reference'; end if;
  if o.status in ('paid','revoked') then return o.status; end if;
  if o.amount_paise <> p_amount_paise then
    update public.payment_orders set status = 'review', admin_note = 'provider amount mismatch', updated_at = now() where id = o.id;
    return 'review';
  end if;
  if p_utr !~ '^[A-Za-z0-9]{6,40}$' or exists (select 1 from private.used_payment_utrs where txn_id = upper(p_utr)) then
    update public.payment_orders set status = 'review', admin_note = 'provider UTR invalid or reused', updated_at = now() where id = o.id;
    return 'review';
  end if;
  insert into private.used_payment_utrs (txn_id, order_id) values (upper(p_utr), o.id);
  update public.payment_orders set utr = p_utr, bank_verified = true, bank_verified_at = now() where id = o.id;
  perform private.activate_subscription(o.id, 'provider_api');
  return 'paid';
end $$;

-- ---------- grants ----------
revoke execute on all functions in schema private from public, anon, authenticated;
revoke execute on function public.provider_payment_update(text,text,integer) from public, anon, authenticated;
grant execute on function public.provider_payment_update(text,text,integer) to service_role;
