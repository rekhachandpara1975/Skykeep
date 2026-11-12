-- Supabase's API connections load pg_safeupdate, which rejects any UPDATE/DELETE without a WHERE clause —
-- including statements inside trigger and RPC functions called from the app or admin panel.
-- These single-row tables were updated without WHERE; give each an explicit one.

create or replace function private.bump_catalog() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update public.plan_catalog set revision = revision + 1, updated_at = now() where true;
  return null;
end $$;

create or replace function public.set_meta_token(p_token text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_owner() then raise exception 'owner only' using errcode = '42501'; end if;
  update private.meta_secrets set capi_token = nullif(trim(p_token), '') where true;
end $$;

create or replace function public.meta_mark(p_ids bigint[], p_ok boolean, p_error text default null) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.meta_events set attempts = attempts + 1,
    status = case when p_ok then 'sent' else 'failed' end,
    sent_at = case when p_ok then now() end, last_error = p_error
  where id = any(p_ids);
  update public.meta_settings set last_success_at = case when p_ok then now() else last_success_at end,
    last_error = case when p_ok then null else p_error end
  where true;
end $$;

revoke execute on function public.meta_mark(bigint[], boolean, text) from public, anon, authenticated;
grant execute on function public.meta_mark(bigint[], boolean, text) to service_role;
revoke execute on all functions in schema private from public, anon, authenticated;
