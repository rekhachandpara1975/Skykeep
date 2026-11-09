-- RPCs used only by edge functions running with the service role
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
  perform private.activate_subscription(o.id);
  return 'paid';
end $$;

create or replace function public.meta_sender_config() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('pixel_id', m.pixel_id, 'test_code', m.test_code, 'enabled', m.enabled, 'token', s.capi_token)
  from public.meta_settings m, private.meta_secrets s
$$;

create or replace function public.meta_pending_events(p_limit int default 50)
returns table (id bigint, event_name text, event_id text, user_id uuid, value_inr numeric, created_at timestamptz, email text, attempts int)
language sql stable security definer set search_path = '' as $$
  select e.id, e.event_name, e.event_id, e.user_id, e.value_inr, e.created_at, u.email::text, e.attempts
  from public.meta_events e left join auth.users u on u.id = e.user_id
  where e.status = 'queued' or (e.status = 'failed' and e.attempts < 5)
  order by e.id limit p_limit
$$;

create or replace function public.meta_mark(p_ids bigint[], p_ok boolean, p_error text default null) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.meta_events set attempts = attempts + 1,
    status = case when p_ok then 'sent' else 'failed' end,
    sent_at = case when p_ok then now() end, last_error = p_error
  where id = any(p_ids);
  update public.meta_settings set last_success_at = case when p_ok then now() else last_success_at end,
    last_error = case when p_ok then null else p_error end;
end $$;

revoke execute on function public.provider_payment_update(text,text,integer), public.meta_sender_config(),
  public.meta_pending_events(int), public.meta_mark(bigint[],boolean,text) from public, anon, authenticated;
grant execute on function public.provider_payment_update(text,text,integer), public.meta_sender_config(),
  public.meta_pending_events(int), public.meta_mark(bigint[],boolean,text), public.enable_play_free_cloud(uuid,text) to service_role;
