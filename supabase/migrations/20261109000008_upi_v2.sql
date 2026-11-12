-- UPI v2 — the server decides, never the phone.
--  * report_result never activates a plan: a valid SUCCESS only moves the order to verification ('review').
--  * the buyer can submit proof: 12-digit UTR (unique) + optional screenshot → 'review'.
--  * the owner approves (one transaction: checks, marks paid, grants plan, logs) or rejects.
--  * unpaid orders expire after 30 minutes ("expired, start again"); proof is still accepted for 24 h.
--  * rate limits on order creation and proof submission; every status change is logged.
--  * Meta: InitiateCheckout when an order is created (Purchase on paid already exists).
-- Status mapping to the spec: pending = created/waiting for payment, submitted/review = pending_verification.

-- ---------- columns, statuses ----------
alter table public.payment_orders drop constraint if exists payment_orders_status_check;
alter table public.payment_orders add constraint payment_orders_status_check
  check (status in ('pending','submitted','review','paid','failed','cancelled','rejected','revoked','expired'));
alter table public.payment_orders
  add column expires_at timestamptz,
  add column proof_screenshot_key text,
  add column proof_submitted_at timestamptz,
  add column utr_source text check (utr_source in ('upi_app','buyer','admin','provider'));
update public.payment_orders set expires_at = created_at + interval '30 minutes' where expires_at is null;
create unique index payment_orders_utr_unique on public.payment_orders (utr) where utr is not null;

-- the client is never trusted: everything goes to verification
update public.payment_settings set activation_mode = 'manual';
alter table public.payment_settings alter column activation_mode set default 'manual';
alter table public.payment_settings drop constraint if exists payment_settings_activation_mode_check;
alter table public.payment_settings add constraint payment_settings_activation_mode_check check (activation_mode = 'manual');

-- ---------- status log (who, when, old → new) ----------
create table public.payment_order_events (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.payment_orders(id) on delete cascade,
  old_status text,
  new_status text not null,
  changed_by uuid,
  note text,
  created_at timestamptz not null default now()
);
create index on public.payment_order_events (order_id, created_at);
alter table public.payment_order_events enable row level security;
create policy poe_read on public.payment_order_events for select to authenticated
  using (public.is_owner() or exists (select 1 from public.payment_orders o where o.id = order_id and o.user_id = auth.uid()));

create or replace function private.log_order_status() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' or new.status is distinct from old.status then
    insert into public.payment_order_events (order_id, old_status, new_status, changed_by, note)
    values (new.id, case when tg_op = 'UPDATE' then old.status end, new.status, auth.uid(), left(new.admin_note, 500));
  end if;
  return null;
end $$;
create trigger payment_orders_log after insert or update of status on public.payment_orders
  for each row execute function private.log_order_status();

-- ---------- expiry ----------
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
  new.expires_at := now() + interval '30 minutes';
  return new;
end $$;

create or replace function private.expire_orders(p_user uuid default null) returns integer
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  update public.payment_orders set status = 'expired', updated_at = now()
   where status = 'pending' and not reported_success and expires_at < now()
     and (p_user is null or user_id = p_user);
  get diagnostics n = row_count;
  return n;
end $$;

-- hourly job now also catches anything the 5-minute job missed
create or replace function private.cancel_stale_orders() returns integer
language plpgsql security definer set search_path = '' as $$
begin
  return private.expire_orders();
end $$;
do $$ begin
  perform cron.unschedule('cancel-stale-orders');
exception when others then null; end $$;
select cron.schedule('expire-orders', '*/5 * * * *', 'select private.expire_orders()');

-- ---------- create_order: expiry + rate limit + one open order per plan ----------
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
         or payee_used is distinct from s.payee_name or duration_days <> p.duration_days);

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

create or replace function private.order_json(o public.payment_orders) returns jsonb
language sql stable as $$
  select jsonb_build_object('order_id', o.id, 'reference', o.reference, 'plan_id', o.plan_id,
    'amount_paise', o.amount_paise, 'amount_inr', round(o.amount_paise / 100.0, 2),
    'upi_id', o.upi_id_used, 'payee_name', o.payee_used, 'status', o.status, 'created_at', o.created_at,
    'expires_at', o.expires_at)
$$;

-- ---------- report_result: the phone's answer is only a hint ----------
create or replace function public.report_result(p_order_id uuid, p_raw text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare o public.payment_orders; v_status text; v_txn text; v_ref text; v_appr text;
begin
  select * into o from public.payment_orders where id = p_order_id and user_id = auth.uid() for update;
  if not found then raise exception 'order not found'; end if;

  -- save raw FIRST
  insert into public.payment_reports (order_id, raw) values (o.id, left(p_raw, 4000));
  update public.payment_orders set raw_response = left(p_raw, 4000), updated_at = now() where id = o.id;

  if o.status not in ('pending','submitted','expired') then
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

  if v_status in ('SUCCESS','SUBMITTED','PENDING') then
    update public.payment_orders set reported_success = (v_status = 'SUCCESS') or reported_success,
      approval_ref = coalesce(v_appr, approval_ref) where id = o.id;
    v_txn := coalesce(v_txn, v_appr);
    if v_status = 'SUCCESS' and v_ref is not distinct from o.reference
       and v_txn ~ '^[A-Za-z0-9]{6,40}$'
       and not exists (select 1 from private.used_payment_utrs where txn_id = upper(v_txn))
       and o.created_at > now() - interval '24 hours' then
      -- looks right → owner verifies against the bank (never activated from the phone)
      update public.payment_orders set status = 'review', txn_id = v_txn,
        utr = case when v_txn ~ '^[0-9]{12}$' and not exists (select 1 from public.payment_orders x where x.utr = v_txn and x.id <> o.id)
                   then v_txn else utr end,
        utr_source = case when v_txn ~ '^[0-9]{12}$' then 'upi_app' else utr_source end,
        updated_at = now() where id = o.id;
      return jsonb_build_object('status', 'review', 'reference', o.reference, 'needs_utr', v_txn !~ '^[0-9]{12}$');
    end if;
    update public.payment_orders set status = 'submitted', updated_at = now() where id = o.id;
    return jsonb_build_object('status', 'pending', 'reference', o.reference, 'needs_utr', true);
  end if;

  -- cancelled / no data / garbage → still waiting; the app offers "I have paid"
  return jsonb_build_object('status', case when o.status = 'expired' then 'expired' else 'pending' end,
    'reference', o.reference, 'needs_utr', true);
end $$;

-- ---------- buyer proof: UTR (+ optional screenshot) ----------
create table public.payment_proofs (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.payment_orders(id) on delete cascade,
  user_id uuid not null,
  utr text not null,
  screenshot_key text,
  result text not null,
  created_at timestamptz not null default now()
);
alter table public.payment_proofs enable row level security;
create policy pp_read on public.payment_proofs for select to authenticated using (user_id = auth.uid() or public.is_owner());

create or replace function public.submit_payment_proof(p_reference text, p_utr text, p_screenshot_key text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); o public.payment_orders; v_utr text := regexp_replace(coalesce(p_utr, ''), '\s', '', 'g');
  v_result text;
begin
  if not public.is_member(v_uid) then raise exception 'login required' using errcode = '42501'; end if;
  if (select count(*) from public.payment_proofs where user_id = v_uid and created_at > now() - interval '1 hour') >= 10 then
    raise exception 'too many attempts — try again in an hour';
  end if;
  select * into o from public.payment_orders where reference = p_reference and user_id = v_uid for update;
  if not found then raise exception 'order not found'; end if;
  if p_screenshot_key is not null and p_screenshot_key not like v_uid::text || '/%' then
    raise exception 'invalid screenshot';
  end if;

  if v_utr !~ '^[0-9]{12}$' then
    v_result := 'bad_format';
  elsif o.status in ('paid','revoked','rejected','cancelled') then
    v_result := o.status;
  elsif o.created_at < now() - interval '24 hours' then
    v_result := 'too_old';
  elsif exists (select 1 from public.payment_orders x where x.utr = v_utr and x.id <> o.id)
     or exists (select 1 from private.used_payment_utrs u where u.txn_id = v_utr and u.order_id <> o.id) then
    v_result := 'duplicate';
  else
    update public.payment_orders set utr = v_utr, utr_source = 'buyer', proof_screenshot_key = coalesce(p_screenshot_key, proof_screenshot_key),
      proof_submitted_at = now(), status = 'review', updated_at = now() where id = o.id;
    v_result := 'review';
  end if;
  insert into public.payment_proofs (order_id, user_id, utr, screenshot_key, result) values (o.id, v_uid, left(v_utr, 40), p_screenshot_key, v_result);
  -- errors are returned (not raised) so the attempt stays counted for the rate limit
  return jsonb_build_object('status', case when v_result in ('bad_format','duplicate','too_old') then 'error' else v_result end,
    'reference', o.reference,
    'error', case v_result when 'bad_format' then 'UTR must be 12 digits'
                           when 'duplicate' then 'this UTR was already used for another payment'
                           when 'too_old' then 'this order is too old — contact support with your UTR' end);
end $$;

-- private bucket for proof screenshots: <user id>/<order reference>/<file>
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('payment-proofs', 'payment-proofs', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;
create policy proofs_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'payment-proofs' and (storage.foldername(name))[1] = auth.uid()::text and public.is_member());
create policy proofs_read on storage.objects for select to authenticated
  using (bucket_id = 'payment-proofs' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_owner()));

-- ---------- owner approve / reject (one transaction each) ----------
create or replace function public.admin_approve_review(p_order_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare o public.payment_orders;
begin
  perform private.require_owner();
  select * into o from public.payment_orders where id = p_order_id for update;
  if not found then raise exception 'order not found'; end if;
  if o.status = 'paid' then return; end if;                                   -- idempotent
  if o.status not in ('review','submitted','expired','pending') then raise exception 'order is %', o.status; end if;
  if o.utr is null and o.txn_id is null then raise exception 'no UTR — use Mark paid with the 12-digit UTR from your bank'; end if;
  if exists (select 1 from private.used_payment_utrs where txn_id = upper(coalesce(o.utr, o.txn_id)) and order_id <> o.id) then
    raise exception 'this UTR was already used for another payment';
  end if;
  insert into private.used_payment_utrs (txn_id, order_id) values (upper(coalesce(o.utr, o.txn_id)), o.id) on conflict do nothing;
  update public.payment_orders set bank_verified = true, bank_verified_at = now(), admin_note = 'approved by owner', updated_at = now() where id = o.id;
  perform private.activate_subscription(o.id, 'admin');
end $$;

create or replace function public.admin_reject_order(p_order_id uuid, p_note text default null) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_owner();
  update public.payment_orders set status = 'rejected', admin_note = coalesce(nullif(p_note, ''), 'rejected by owner'), updated_at = now()
   where id = p_order_id and status in ('pending','submitted','review','expired','failed');
  if not found then raise exception 'order cannot be rejected'; end if;
end $$;

-- activation through approve / mark paid / provider only (report_result no longer calls it)
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

-- ---------- order status for the app ----------
create or replace function public.order_status(p_order_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare o public.payment_orders;
begin
  perform private.expire_orders(auth.uid());
  select * into o from public.payment_orders where id = p_order_id and user_id = auth.uid();
  if not found then return null; end if;
  return jsonb_build_object('status', case when o.status = 'submitted' then 'pending' else o.status end,
    'reference', o.reference, 'amount_inr', round(o.amount_paise/100.0, 2), 'utr', o.utr,
    'expires_at', o.expires_at, 'payee_name', o.payee_used, 'upi_id', o.upi_id_used);
end $$;

-- payee is shown to every payer by their UPI app anyway; the plans page says "You will pay ₹X to <payee>"
create or replace function public.plan_offers() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'free_plan_ids', coalesce((select jsonb_agg(p.id) from public.plans p
                       where p.active and public.plan_is_free_for_me(p.id)), '[]'::jsonb),
    'payments_available', public.payments_available(),
    'plans_visible', public.plans_visible_for_me(),
    'payee_name', case when public.payments_available() then (select payee_name from public.payment_settings limit 1) end)
$$;

-- ---------- Meta: InitiateCheckout ----------
alter table public.meta_events drop constraint if exists meta_events_event_name_check;
alter table public.meta_events add constraint meta_events_event_name_check
  check (event_name in ('Lead','CompleteRegistration','InitiateCheckout','Purchase'));
create or replace function private.enqueue_checkout() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.meta_events (event_name, event_id, user_id, order_id, value_inr)
  values ('InitiateCheckout', 'checkout_' || new.id, new.user_id, new.id, new.amount_paise / 100.0) on conflict do nothing;
  return null;
end $$;
create trigger payment_orders_checkout after insert on public.payment_orders
  for each row execute function private.enqueue_checkout();

revoke execute on all functions in schema private from public, anon, authenticated;
revoke execute on function public.submit_payment_proof(text,text,text) from public, anon;
grant execute on function public.submit_payment_proof(text,text,text) to authenticated;

-- ---------- admin list with proof columns ----------
drop function if exists public.admin_orders(text, int);
create function public.admin_orders(p_filter text default 'all', p_limit int default 200)
returns table (id uuid, created_at timestamptz, user_id uuid, email text, plan_name text, amount_paise int,
  reference text, txn_id text, utr text, utr_source text, upi_id_used text, status text, raw_response text,
  bank_verified boolean, paid_at timestamptz, admin_note text, expires_at timestamptz,
  proof_screenshot_key text, proof_submitted_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
declare v_today timestamptz := date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
begin
  perform private.require_owner();
  return query select o.id, o.created_at, o.user_id, u.email::text, p.name, o.amount_paise, o.reference, o.txn_id, o.utr, o.utr_source,
    o.upi_id_used, o.status, o.raw_response, o.bank_verified, o.paid_at, o.admin_note, o.expires_at,
    o.proof_screenshot_key, o.proof_submitted_at
  from public.payment_orders o left join auth.users u on u.id = o.user_id left join public.plans p on p.id = o.plan_id
  where case p_filter
    when 'all' then true
    when 'verify_today' then o.status = 'paid' and not o.bank_verified and o.paid_at >= v_today
    when 'review' then o.status in ('review','submitted')
    else o.status = p_filter end
  order by (o.status = 'review') desc, o.created_at desc limit p_limit;
end $$;
revoke execute on function public.admin_orders(text, int) from public, anon;
