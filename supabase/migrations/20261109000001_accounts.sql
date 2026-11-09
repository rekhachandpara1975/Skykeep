-- PART A.1/A.2/A.6 — accounts, attribution, app mode, helpers
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- ---------- profiles ----------
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  avatar_url text,
  is_guest boolean not null default true,
  used_bytes bigint not null default 0 check (used_bytes >= 0),
  ads_access_status text not null default 'none'
    check (ads_access_status in ('none','pending','approved','rejected')),
  play_verified boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;

create or replace function private.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, is_guest, display_name)
  values (new.id, coalesce(new.is_anonymous, false), nullif(split_part(coalesce(new.email,''),'@',1),''))
  on conflict (id) do nothing;
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function private.handle_new_user();

-- guest -> email upgrade keeps the same id; only flip is_guest
create or replace function private.handle_user_upgrade() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if coalesce(old.is_anonymous,false) and not coalesce(new.is_anonymous,false) then
    update public.profiles set is_guest = false,
      display_name = coalesce(display_name, nullif(split_part(coalesce(new.email,''),'@',1),''))
    where id = new.id;
  end if;
  return new;
end $$;
create trigger on_auth_user_upgraded after update of is_anonymous on auth.users
  for each row execute function private.handle_user_upgrade();

-- ---------- admins ----------
create table public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','content')),
  email text,
  created_at timestamptz not null default now()
);
alter table public.admins enable row level security;

create or replace function public.is_owner(uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.admins a where a.user_id = uid and a.role = 'owner')
$$;
create or replace function public.is_admin(uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.admins a where a.user_id = uid)
$$;
create or replace function public.is_member(uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from auth.users u where u.id = uid and not coalesce(u.is_anonymous, false))
$$;

-- keep at least one owner
create or replace function private.keep_last_owner() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if old.role = 'owner' and (tg_op = 'DELETE' or new.role <> 'owner')
     and (select count(*) from public.admins where role = 'owner') <= 1 then
    raise exception 'cannot remove the last owner';
  end if;
  return coalesce(new, old);
end $$;
create trigger admins_keep_last_owner before update or delete on public.admins
  for each row execute function private.keep_last_owner();

create policy admins_read on public.admins for select to authenticated using (public.is_admin());
create policy admins_owner_write on public.admins for all to authenticated
  using (public.is_owner()) with check (public.is_owner());

create table public.consents (
  user_id uuid not null references auth.users(id) on delete cascade,
  policy_version text not null,
  accepted_at timestamptz not null default now(),
  primary key (user_id, policy_version)
);
alter table public.consents enable row level security;
create policy consents_own_read on public.consents for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
create policy consents_own_insert on public.consents for insert to authenticated
  with check (user_id = auth.uid() and public.is_member());

create or replace function public.has_consent(uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.consents c where c.user_id = uid)
$$;

-- ---------- attribution (first touch, permanent) ----------
create table private.user_sources (
  user_id uuid primary key references auth.users(id) on delete cascade,
  source text not null check (source in ('ads','organic')),
  created_at timestamptz not null default now()
);
create or replace function private.block_source_change() returns trigger
language plpgsql as $$
begin
  -- cascade from auth.users deletion is the only allowed removal
  if tg_op = 'DELETE' and not exists (select 1 from auth.users where id = old.user_id) then
    return old;
  end if;
  raise exception 'user source is immutable';
end $$;
create trigger user_sources_immutable before update or delete on private.user_sources
  for each row execute function private.block_source_change();

create or replace function public.source_of(uid uuid default auth.uid()) returns text
language sql stable security definer set search_path = '' as $$
  select coalesce((select s.source from private.user_sources s where s.user_id = uid), 'organic')
$$;

create table public.installs (
  install_id text primary key check (length(install_id) between 8 and 128),
  user_id uuid references auth.users(id) on delete set null,
  referrer_status text,
  raw_referrer text,
  secret_hash text not null,
  source text not null check (source in ('ads','organic')),
  utm_source text,
  utm_campaign text,
  created_at timestamptz not null default now()
);
alter table public.installs enable row level security;
create policy installs_admin_read on public.installs for select to authenticated using (public.is_admin());

create or replace function private.referrer_param(raw text, key text) returns text
language sql immutable as $$
  select (regexp_match(coalesce(raw,''), '(?:^|[&?])' || key || '=([^&]*)', 'i'))[1]
$$;

create or replace function public.record_install(
  p_install_id text, p_referrer_status text, p_raw_referrer text, p_install_secret text
) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_src text;
  v_hash text := encode(sha256(convert_to(coalesce(p_install_secret,''), 'UTF8')), 'hex');
  v_existing public.installs;
  v_utm text := lower(coalesce(private.referrer_param(p_raw_referrer, 'utm_source'), ''));
begin
  if v_uid is null then raise exception 'not signed in'; end if;
  if length(coalesce(p_install_secret,'')) < 16 then raise exception 'bad install secret'; end if;
  select * into v_existing from public.installs where install_id = p_install_id;
  if found then
    if v_existing.secret_hash <> v_hash then raise exception 'install secret mismatch'; end if;
    v_src := v_existing.source;
    if v_existing.user_id is null then
      update public.installs set user_id = v_uid where install_id = p_install_id;
    end if;
  else
    v_src := case when v_utm in ('meta','facebook','instagram','ig') then 'ads' else 'organic' end;
    insert into public.installs (install_id, user_id, referrer_status, raw_referrer, secret_hash, source, utm_source, utm_campaign)
    values (p_install_id, v_uid, p_referrer_status, left(p_raw_referrer, 2000), v_hash, v_src,
            nullif(v_utm,''), private.referrer_param(p_raw_referrer, 'utm_campaign'));
  end if;
  insert into private.user_sources (user_id, source) values (v_uid, v_src) on conflict (user_id) do nothing;
  return public.source_of(v_uid);
end $$;

create table public.ad_clicks (
  id bigint generated always as identity primary key,
  fbclid text, fbc text, fbp text, ip text, user_agent text, path text,
  created_at timestamptz not null default now()
);
alter table public.ad_clicks enable row level security;
create policy ad_clicks_owner_read on public.ad_clicks for select to authenticated using (public.is_owner());

-- ---------- app mode ----------
create table public.app_mode (
  id boolean primary key default true check (id),
  free_mode boolean not null default false,
  free_plans_for text not null default 'none' check (free_plans_for in ('none','organic','ads','everyone')),
  promo_id uuid,
  plans_visible_for text not null default 'everyone' check (plans_visible_for in ('everyone','ads','organic','none')),
  updated_at timestamptz not null default now()
);
insert into public.app_mode default values;
alter table public.app_mode enable row level security;
create policy app_mode_read on public.app_mode for select to anon, authenticated using (true);
create policy app_mode_owner_update on public.app_mode for update to authenticated
  using (public.is_owner()) with check (public.is_owner());

create or replace function private.app_mode_promo() returns trigger
language plpgsql as $$
begin
  if old.free_plans_for = 'none' and new.free_plans_for <> 'none' then
    new.promo_id := gen_random_uuid();
  end if;
  new.updated_at := now();
  return new;
end $$;
create trigger app_mode_promo before update on public.app_mode
  for each row execute function private.app_mode_promo();

create or replace function public.free_mode() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select free_mode from public.app_mode limit 1), false)
$$;

create policy profiles_read on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_admin());
create policy profiles_update_own on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- users may edit only name/avatar on their own row
create or replace function private.profiles_guard() returns trigger
language plpgsql as $$
begin
  if current_user in ('authenticated','anon') and not public.is_owner() then
    new.is_guest := old.is_guest; new.used_bytes := old.used_bytes;
    new.ads_access_status := old.ads_access_status; new.play_verified := old.play_verified;
    new.created_at := old.created_at;
  end if;
  return new;
end $$;
create trigger profiles_guard before update on public.profiles
  for each row execute function private.profiles_guard();
