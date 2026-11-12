-- Automatic UPI verification from the owner's bank credit SMS (forwarded to the bank-sms edge function).
-- The phone's UPI result is still only a hint: a plan is activated automatically ONLY when a bank credit
-- (amount + UTR from the bank's own SMS) matches an open order. Everything else stays in "To verify".
--
-- Matching (in this order):
--   1. UTR: the bank's UTR equals the order's UTR / txn id / approval ref (from the UPI app or typed by the buyer)
--      and the amount is exactly the order amount → paid.
--   2. Amount: no order has that UTR, and EXACTLY ONE open order has that exact amount, created in the
--      2 hours before the credit → paid. Two or more → wait for the buyer's UTR (or the owner).
--   Amount differs → order goes to review with a note; never auto-activated.
-- A credit that arrives before the buyer's UTR is kept; when the UTR is reported later the match runs then.

create table private.bank_credits (
  id bigint generated always as identity primary key,
  utr text unique,
  amount_paise integer not null check (amount_paise > 0),
  payer text,
  raw text,
  source text not null default 'sms',
  received_at timestamptz not null default now(),
  order_id uuid references public.payment_orders(id) on delete set null,
  matched_at timestamptz,
  note text
);
create index on private.bank_credits (received_at desc);
alter table private.bank_credits enable row level security;

-- order still waiting for money (incl. expired up to 48 h: people pay late)
create or replace function private.order_open(o public.payment_orders) returns boolean
language sql stable as $$
  select o.status in ('pending','submitted','review','expired') and o.created_at > now() - interval '48 hours'
$$;

create or replace function private.settle_credit(p_order_id uuid, p_credit_id bigint, p_how text) returns text
language plpgsql security definer set search_path = '' as $$
declare o public.payment_orders; c private.bank_credits;
begin
  select * into o from public.payment_orders where id = p_order_id for update;
  select * into c from private.bank_credits where id = p_credit_id for update;
  if not private.order_open(o) or c.order_id is not null then return 'skipped'; end if;

  if o.amount_paise <> c.amount_paise then
    update private.bank_credits set order_id = o.id, matched_at = now(),
      note = format('amount mismatch: bank ₹%s, order ₹%s', c.amount_paise / 100.0, o.amount_paise / 100.0) where id = c.id;
    update public.payment_orders set status = 'review', updated_at = now(),
      admin_note = format('bank credit UTR %s is ₹%s but the order is ₹%s — check before approving',
                          coalesce(c.utr, '?'), c.amount_paise / 100.0, o.amount_paise / 100.0)
     where id = o.id;
    return 'amount_mismatch';
  end if;

  if c.utr is not null and exists (select 1 from private.used_payment_utrs u where u.txn_id = upper(c.utr) and u.order_id <> o.id) then
    update private.bank_credits set note = 'UTR already used for another order' where id = c.id;
    return 'utr_used';
  end if;

  update private.bank_credits set order_id = o.id, matched_at = now(), note = 'auto-verified (' || p_how || ')' where id = c.id;
  if c.utr is not null then
    insert into private.used_payment_utrs (txn_id, order_id) values (upper(c.utr), o.id) on conflict do nothing;
  end if;
  update public.payment_orders set
      utr = case when c.utr is not null and not exists (select 1 from public.payment_orders x where x.utr = c.utr and x.id <> o.id)
                 then c.utr else utr end,
      utr_source = case when utr is null and c.utr is not null then 'provider' else utr_source end,
      bank_verified = true, bank_verified_at = now(),
      admin_note = 'auto-verified from bank SMS (' || p_how || ')', updated_at = now()
   where id = o.id;
  perform private.activate_subscription(o.id, 'provider_api');
  return 'paid';
end $$;

-- a bank credit arrived: find its order
create or replace function private.match_credit(p_credit_id bigint) returns text
language plpgsql security definer set search_path = '' as $$
declare c private.bank_credits; v_order uuid; v_n int;
begin
  select * into c from private.bank_credits where id = p_credit_id;
  if c.order_id is not null then return 'already_matched'; end if;

  if c.utr is not null then
    select o.id into v_order from public.payment_orders o
     where private.order_open(o) and c.utr in (o.utr, o.txn_id, o.approval_ref)
     order by o.created_at desc limit 1;
    if v_order is not null then return private.settle_credit(v_order, c.id, 'UTR'); end if;
  end if;

  select count(*), min(o.id::text)::uuid into v_n, v_order from public.payment_orders o
   where private.order_open(o) and o.amount_paise = c.amount_paise
     and o.created_at between c.received_at - interval '2 hours' and c.received_at + interval '1 minute'
     and (o.utr is null or o.utr = c.utr);
  if v_n = 1 then return private.settle_credit(v_order, c.id, 'amount'); end if;

  update private.bank_credits set note = case when v_n > 1
      then format('%s open orders with ₹%s — waiting for the buyer''s UTR', v_n, c.amount_paise / 100.0)
      else 'no matching order yet — waiting for the buyer''s UTR' end
   where id = c.id;
  return case when v_n > 1 then 'ambiguous' else 'unmatched' end;
end $$;

-- an order got a UTR / txn id (UPI app answer, buyer proof, owner): look for a bank credit that came first
create or replace function private.match_order(p_order_id uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare o public.payment_orders; v_credit bigint;
begin
  select * into o from public.payment_orders where id = p_order_id;
  if not private.order_open(o) then return 'closed'; end if;
  select c.id into v_credit from private.bank_credits c
   where c.order_id is null and c.utr is not null and c.utr in (o.utr, o.txn_id, o.approval_ref)
     and c.received_at > o.created_at - interval '5 minutes'
   order by c.received_at limit 1;
  if v_credit is null then return 'no_credit'; end if;
  return private.settle_credit(o.id, v_credit, 'UTR');
end $$;

create or replace function private.orders_try_match() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if pg_trigger_depth() > 1 then return null; end if;   -- settle_credit's own updates
  if new.status in ('pending','submitted','review','expired')
     and (new.utr, new.txn_id, new.approval_ref) is distinct from (old.utr, old.txn_id, old.approval_ref)
     and coalesce(new.utr, new.txn_id, new.approval_ref) is not null then
    perform private.match_order(new.id);
  end if;
  return null;
end $$;
create trigger payment_orders_try_match after update of utr, txn_id, approval_ref on public.payment_orders
  for each row execute function private.orders_try_match();

-- called only by the bank-sms edge function (service role) after it parsed a credit SMS
create or replace function public.bank_credit_received(p_utr text, p_amount_paise integer, p_raw text default null, p_payer text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id bigint; v_utr text := nullif(regexp_replace(coalesce(p_utr, ''), '\s', '', 'g'), ''); v_result text;
begin
  if p_amount_paise is null or p_amount_paise <= 0 then raise exception 'amount required'; end if;
  if v_utr is not null and v_utr !~ '^[A-Za-z0-9]{6,40}$' then v_utr := null; end if;
  insert into private.bank_credits (utr, amount_paise, payer, raw)
  values (v_utr, p_amount_paise, left(p_payer, 120), left(p_raw, 1000))
  on conflict (utr) do nothing returning id into v_id;
  if v_id is null then return jsonb_build_object('result', 'duplicate'); end if;
  v_result := private.match_credit(v_id);
  return jsonb_build_object('result', v_result, 'credit_id', v_id);
end $$;

-- admin: recent bank credits and what they matched
create or replace function public.admin_bank_credits(p_limit int default 30)
returns table (id bigint, received_at timestamptz, utr text, amount_paise integer, payer text, note text, reference text, order_status text)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform private.require_owner();
  return query select c.id, c.received_at, c.utr, c.amount_paise, c.payer, c.note, o.reference, o.status
    from private.bank_credits c left join public.payment_orders o on o.id = c.order_id
   order by c.received_at desc limit p_limit;
end $$;

revoke execute on all functions in schema private from public, anon, authenticated;
revoke execute on function public.bank_credit_received(text, integer, text, text) from public, anon, authenticated;
grant execute on function public.bank_credit_received(text, integer, text, text) to service_role;
revoke execute on function public.admin_bank_credits(int) from public, anon;
