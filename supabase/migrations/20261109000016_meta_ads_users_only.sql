-- Meta Conversions API: only users who installed from one of our ad links are ever reported
-- (matches the privacy policy; Google Play users are never sent to Meta).
create or replace function private.is_ads_user(uid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select s.source = 'ads' from private.user_sources s where s.user_id = uid), false)
$$;

create or replace function private.enqueue_registration() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if old.is_guest and not new.is_guest and private.is_ads_user(new.id) then
    insert into public.meta_events (event_name, event_id, user_id)
    values ('CompleteRegistration', 'reg_' || new.id, new.id) on conflict do nothing;
  end if;
  return null;
end $$;

create or replace function private.enqueue_purchase() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.status = 'paid' and old.status <> 'paid' and private.is_ads_user(new.user_id) then
    insert into public.meta_events (event_name, event_id, user_id, order_id, value_inr)
    values ('Purchase', 'order_' || new.id, new.user_id, new.id, new.amount_paise / 100.0) on conflict do nothing;
  end if;
  return null;
end $$;

create or replace function private.enqueue_checkout() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if private.is_ads_user(new.user_id) then
    insert into public.meta_events (event_name, event_id, user_id, order_id, value_inr)
    values ('InitiateCheckout', 'checkout_' || new.id, new.user_id, new.id, new.amount_paise / 100.0) on conflict do nothing;
  end if;
  return null;
end $$;

-- never send anything already queued for users who did not come from an ad
delete from public.meta_events e
 where e.status in ('queued','failed') and e.user_id is not null and not private.is_ads_user(e.user_id);

revoke execute on all functions in schema private from public, anon, authenticated;
