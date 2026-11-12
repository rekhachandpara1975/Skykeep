-- Owner's choice: activate the plan as soon as the buyer's UPI app answers SUCCESS (the UPI intent callback).
--  * Admin › Payments has a switch: "instant" (default now) or "manual" (SUCCESS → To verify, as before).
--  * The server still checks everything it can before activating:
--      the answer's txnRef is this order's reference, the order is open and < 2 hours old,
--      a transaction id / UTR is present and was never used before, and the buyer has had
--      fewer than 3 instant activations in 24 hours (more → To verify).
--  * Every instant activation lands in "Activated today — verify against bank" so the owner can
--    tick it off or Revoke it. FAILURE → failed. Cancelled / no answer → still waiting ("I have paid").
--  * Bank-SMS matching must not hand an already-paid order's money to another buyer's open order.

alter table public.payment_settings drop constraint if exists payment_settings_activation_mode_check;
alter table public.payment_settings add constraint payment_settings_activation_mode_check
  check (activation_mode in ('instant','manual'));
alter table public.payment_settings alter column activation_mode set default 'instant';
update public.payment_settings set activation_mode = 'instant' where activation_mode <> 'instant';

create or replace function public.report_result(p_order_id uuid, p_raw text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare o public.payment_orders; v_status text; v_txn text; v_ref text; v_appr text; v_mode text; v_auto int;
  v_utr_ok boolean;
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
    -- prefer the 12-digit bank reference (UTR) when the app gives one
    v_txn := case when v_appr ~ '^[0-9]{12}$' then v_appr else coalesce(v_txn, v_appr) end;

    if v_status = 'SUCCESS' and v_ref is not distinct from o.reference
       and v_txn ~ '^[A-Za-z0-9]{6,40}$'
       and not exists (select 1 from private.used_payment_utrs where txn_id = upper(v_txn))
       and o.created_at > now() - interval '24 hours' then
      v_utr_ok := v_txn ~ '^[0-9]{12}$' and not exists (select 1 from public.payment_orders x where x.utr = v_txn and x.id <> o.id);
      select activation_mode into v_mode from public.payment_settings limit 1;
      select count(*) into v_auto from public.payment_orders
        where user_id = o.user_id and auto_activated and paid_at > now() - interval '24 hours';

      if v_mode = 'instant' and v_auto < 3 and o.created_at > now() - interval '2 hours' then
        -- instant: the UPI app said SUCCESS for this exact order → plan on now
        insert into private.used_payment_utrs (txn_id, order_id) values (upper(v_txn), o.id);
        update public.payment_orders set auto_activated = true, txn_id = v_txn,
          utr = case when v_utr_ok then v_txn else utr end,
          utr_source = case when v_utr_ok then 'upi_app' else utr_source end,
          admin_note = 'activated instantly from the UPI app''s SUCCESS — verify against bank', updated_at = now()
         where id = o.id;
        perform private.activate_subscription(o.id, 'upi_app');
        -- a bank SMS that came first confirms it straight away
        update public.payment_orders set bank_verified = true, bank_verified_at = now(),
               admin_note = 'activated from the UPI app''s SUCCESS, confirmed by bank SMS'
         where id = o.id and exists (select 1 from private.bank_credits c
                                      where c.order_id is null and c.utr = v_txn and c.amount_paise = o.amount_paise);
        update private.bank_credits set order_id = o.id, matched_at = now(), note = 'confirms instant UPI activation'
         where order_id is null and utr = v_txn and amount_paise = o.amount_paise;
        return jsonb_build_object('status', 'paid', 'reference', o.reference);
      end if;

      -- manual mode, too many instant activations, or an old order → owner verifies
      update public.payment_orders set status = 'review', txn_id = v_txn,
        utr = case when v_utr_ok then v_txn else utr end,
        utr_source = case when v_utr_ok then 'upi_app' else utr_source end,
        admin_note = case when v_mode = 'instant' then 'UPI app said SUCCESS but instant limits hit — verify' else admin_note end,
        updated_at = now() where id = o.id;
      return jsonb_build_object('status', 'review', 'reference', o.reference, 'needs_utr', not v_utr_ok);
    end if;
    update public.payment_orders set status = 'submitted', updated_at = now() where id = o.id;
    return jsonb_build_object('status', 'pending', 'reference', o.reference, 'needs_utr', true);
  end if;

  -- cancelled / no data / garbage → still waiting; the app offers "I have paid"
  return jsonb_build_object('status', case when o.status = 'expired' then 'expired' else 'pending' end,
    'reference', o.reference, 'needs_utr', true);
end $$;

-- bank credit for an order that the UPI app already activated: confirm it, never give it to someone else
create or replace function private.match_credit(p_credit_id bigint) returns text
language plpgsql security definer set search_path = '' as $$
declare c private.bank_credits; v_order uuid; v_n int;
begin
  select * into c from private.bank_credits where id = p_credit_id;
  if c.order_id is not null then return 'already_matched'; end if;

  if c.utr is not null then
    select o.id into v_order from public.payment_orders o
     where o.status = 'paid' and c.utr in (o.utr, o.txn_id, o.approval_ref) limit 1;
    if v_order is not null then
      update private.bank_credits set order_id = v_order, matched_at = now(), note = 'confirms an order already paid' where id = c.id;
      update public.payment_orders set bank_verified = true, bank_verified_at = now(), updated_at = now()
       where id = v_order and amount_paise = c.amount_paise and not bank_verified;
      return 'confirmed';
    end if;

    select o.id into v_order from public.payment_orders o
     where private.order_open(o) and c.utr in (o.utr, o.txn_id, o.approval_ref)
     order by o.created_at desc limit 1;
    if v_order is not null then return private.settle_credit(v_order, c.id, 'UTR'); end if;
  end if;

  -- same amount as an order the UPI app activated but the bank hasn't confirmed → could be that payment
  if exists (select 1 from public.payment_orders o
              where o.status = 'paid' and o.auto_activated and not o.bank_verified and o.amount_paise = c.amount_paise
                and o.paid_at between c.received_at - interval '2 hours' and c.received_at + interval '5 minutes') then
    update private.bank_credits set note = 'same amount as an order already activated by the UPI app — check manually' where id = c.id;
    return 'ambiguous';
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

-- owner switch (Admin › Payments)
create or replace function public.admin_set_activation_mode(p_mode text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_owner();
  if p_mode not in ('instant','manual') then raise exception 'mode must be instant or manual'; end if;
  update public.payment_settings set activation_mode = p_mode where true;
end $$;
revoke execute on function public.admin_set_activation_mode(text) from public, anon;
grant execute on function public.admin_set_activation_mode(text) to authenticated;
