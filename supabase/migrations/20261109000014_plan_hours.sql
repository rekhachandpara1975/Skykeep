-- Plans can last a number of HOURS (e.g. 6 hours, 12 hours) instead of days.
--  * plans.duration_hours: set → the plan lasts that many hours; null → duration_days as before.
--    duration_days is kept filled (hours rounded up to whole days) so older screens still show something sensible.
--  * Orders snapshot the hours too; activation, free claims and stacking use the exact length.

alter table public.plans add column duration_hours integer check (duration_hours between 1 and 8784);
alter table public.payment_orders add column duration_hours integer;

create or replace function private.plans_hours_days() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.duration_hours is not null then new.duration_days := greatest(1, ceil(new.duration_hours / 24.0)::int); end if;
  return new;
end $$;
create trigger plans_hours_days before insert or update of duration_hours, duration_days on public.plans
  for each row execute function private.plans_hours_days();

create or replace function private.plan_length(p_days integer, p_hours integer) returns interval
language sql immutable as $$
  select case when p_hours is not null then make_interval(hours => p_hours) else make_interval(days => p_days) end
$$;

create or replace function private.orders_snapshot() returns trigger
language plpgsql security definer set search_path = '' as $$
declare p public.plans; s public.payment_settings;
begin
  select * into p from public.plans where id = new.plan_id;
  select * into s from public.payment_settings limit 1;
  new.amount_paise := p.price_inr * 100;
  new.duration_days := p.duration_days;
  new.duration_hours := p.duration_hours;
  new.upi_id_used := s.upi_id;
  new.payee_used := s.payee_name;
  new.reference := 'SK' || to_char(now() at time zone 'Asia/Kolkata', 'YYYYMMDD')
                   || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  new.status := 'pending';
  new.expires_at := now() + interval '30 minutes';
  return new;
end $$;

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

  perform private.expire_orders(v_uid);
  update public.payment_orders set status = 'cancelled', updated_at = now()
  where user_id = v_uid and status = 'pending' and not reported_success
    and (plan_id <> p_plan_id or amount_paise <> p.price_inr * 100 or upi_id_used is distinct from s.upi_id
         or payee_used is distinct from s.payee_name or duration_days <> p.duration_days
         or duration_hours is distinct from p.duration_hours);

  -- reuse the open order for this plan (double tap / come back within 30 min)
  select * into o from public.payment_orders
  where user_id = v_uid and status = 'pending' and plan_id = p_plan_id and not reported_success and expires_at > now()
  order by created_at desc limit 1;
  if not found then
    if (select count(*) from public.payment_orders where user_id = v_uid and created_at > now() - interval '1 hour') >= 10 then
      raise exception 'too many payment attempts — try again in an hour';
    end if;
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
  values (o.user_id, o.plan_id, o.id, 'paid', v_base + private.plan_length(o.duration_days, o.duration_hours))
  returning * into sub;
  update public.payment_orders set status = 'paid', paid_at = now(), updated_at = now() where id = o.id;
  perform private.flag_organic_pending(o.user_id);
  return sub;
end $$;

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
  values (v_uid, p.id, 'free_promo', m.promo_id, now() + private.plan_length(p.duration_days, p.duration_hours)) returning * into sub;
  insert into public.free_plan_claims (user_id, plan_id, promo_id, subscription_id) values (v_uid, p.id, m.promo_id, sub.id);
  perform private.flag_organic_pending(v_uid);
  return jsonb_build_object('plan_name', p.name, 'ends_at', sub.ends_at);
end $$;

revoke execute on all functions in schema private from public, anon, authenticated;
