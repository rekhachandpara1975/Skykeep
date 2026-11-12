-- Guests (automatic anonymous login) can buy plans. Their plan works at once (2 TB, full videos, downloads);
-- adding an email later keeps the same account, so the plan stays. Free/ads-only content rules for guests are unchanged.

-- a paying guest who came from ads sees ads content like an ads member (organic still needs approval, as for members)
create or replace function public.has_ads_access(uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.uid_ok(uid) and (public.is_admin(uid) or (public.is_member(uid) and (
         public.source_of(uid) = 'ads'
      or (coalesce((select p.ads_access_status from public.profiles p where p.id = uid),'none') = 'approved'
          and (public.free_mode() or public.has_active_plan(uid)))))
    or (not public.free_mode() and public.has_active_plan(uid) and public.source_of(uid) = 'ads'))
$$;

create or replace function public.has_full_access(uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.uid_ok(uid) and (public.is_admin(uid)
    or (public.is_member(uid) and case when public.free_mode() then public.has_ads_access(uid) else public.has_active_plan(uid) end)
    or (not public.free_mode() and public.has_active_plan(uid)))   -- paying guest
$$;

create or replace function public.create_order(p_plan_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  p public.plans; s public.payment_settings; o public.payment_orders;
begin
  if v_uid is null then raise exception 'login required' using errcode = '42501'; end if;  -- guests may buy
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

create or replace function public.submit_payment_proof(p_reference text, p_utr text, p_screenshot_key text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); o public.payment_orders; v_utr text := regexp_replace(coalesce(p_utr, ''), '\s', '', 'g');
  v_result text;
begin
  if v_uid is null then raise exception 'login required' using errcode = '42501'; end if;
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

create or replace function public.can_view(p_item_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'visible', i.id is not null and public.post_visible(i.post_id),
    'full', i.id is not null and public.post_visible(i.post_id) and (not i.is_premium or public.has_full_access()),
    'download', i.id is not null and public.post_visible(i.post_id) and (public.is_member() or public.has_active_plan())
                and (not i.is_premium or public.has_full_access()),
    'trailer', i.id is not null and public.post_visible(i.post_id) and i.is_premium
               and not public.has_full_access() and i.trailer_key is not null)
  from (select 1) x left join public.post_items i on i.id = p_item_id
$$;

drop policy if exists proofs_insert on storage.objects;
create policy proofs_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'payment-proofs' and (storage.foldername(name))[1] = auth.uid()::text);
