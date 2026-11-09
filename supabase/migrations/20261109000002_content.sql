-- PART A.3/A.4/A.5 — access helpers, channels, posts, storage, cloud
create table public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  plan_id uuid,
  order_id uuid unique,
  kind text not null check (kind in ('paid','free_promo','grant')),
  promo_id uuid,
  starts_at timestamptz not null default now(),
  ends_at timestamptz not null,
  status text not null default 'active' check (status in ('active','revoked')),
  created_at timestamptz not null default now()
);
create index on public.subscriptions (user_id, ends_at desc);
alter table public.subscriptions enable row level security;
create policy subs_read on public.subscriptions for select to authenticated
  using (user_id = auth.uid() or public.is_owner());

create or replace function public.has_active_plan(uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.subscriptions s
    where s.user_id = uid and s.status = 'active' and s.ends_at > now())
$$;

-- ads users always; organic only when approved AND (free mode OR active plan)
create or replace function public.has_ads_access(uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.is_admin(uid)
      or public.source_of(uid) = 'ads'
      or (coalesce((select p.ads_access_status from public.profiles p where p.id = uid),'none') = 'approved'
          and (public.free_mode() or public.has_active_plan(uid)))
$$;

-- full (premium) video access
create or replace function public.has_full_access(uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.is_admin(uid)
      or (public.has_ads_access(uid) and (public.free_mode() or public.has_active_plan(uid)))
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
    when public.has_active_plan(uid) then 2199023255552::bigint            -- 2 TB
    when public.is_member(uid) and (public.free_mode()
         or coalesce((select play_verified from public.profiles where id = uid), false))
      then 16106127360::bigint                                              -- 15 GB
    else 0::bigint end
$$;

-- ---------- channels ----------
create table public.channels (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(name) between 2 and 80),
  description text check (length(description) <= 2000),
  category text,
  tags text[] not null default '{}',
  icon_url text,
  audience text not null default 'all' check (audience in ('all','organic','ads')),
  status text not null default 'published' check (status in ('draft','published','active')),
  review_status text not null default 'pending' check (review_status in ('pending','approved','rejected')),
  created_by uuid references auth.users(id) on delete set null,
  members_count integer not null default 0,
  hidden boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.channels enable row level security;

create table public.admin_channel_access (
  user_id uuid not null references public.admins(user_id) on delete cascade,
  channel_id uuid not null references public.channels(id) on delete cascade,
  primary key (user_id, channel_id)
);
alter table public.admin_channel_access enable row level security;
create policy aca_read on public.admin_channel_access for select to authenticated
  using (user_id = auth.uid() or public.is_owner());
create policy aca_owner_write on public.admin_channel_access for all to authenticated
  using (public.is_owner()) with check (public.is_owner());

create or replace function public.can_manage_channel(cid uuid, uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.is_owner(uid) or exists (select 1 from public.admin_channel_access a
    where a.user_id = uid and a.channel_id = cid)
$$;

-- creator may upload only to own approved + published channel
create or replace function public.can_upload_channel(cid uuid, uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.can_manage_channel(cid, uid) or exists (select 1 from public.channels c
    where c.id = cid and c.created_by = uid and c.review_status = 'approved'
      and c.status in ('published','active') and not c.hidden
      and public.is_member(uid) and public.has_consent(uid))
$$;

create or replace function public.channel_visible(cid uuid, uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.channels c where c.id = cid and (
    public.can_manage_channel(c.id, uid) or c.created_by = uid or
    (c.review_status = 'approved' and c.status in ('published','active') and not c.hidden
     and public.can_see_audience(c.audience, uid))))
$$;

create policy channels_read on public.channels for select to anon, authenticated
  using (public.channel_visible(id));
create policy channels_insert on public.channels for insert to authenticated
  with check (public.is_admin() or (public.is_member() and public.has_consent() and created_by = auth.uid()));
create policy channels_update on public.channels for update to authenticated
  using (public.can_manage_channel(id) or created_by = auth.uid())
  with check (public.can_manage_channel(id) or created_by = auth.uid());
create policy channels_delete on public.channels for delete to authenticated using (public.is_owner());

create or replace function private.channels_guard() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then return new; end if; -- service role / migrations
  if tg_op = 'INSERT' then
    if public.is_admin() then
      new.review_status := 'approved';
    else
      new.review_status := 'pending'; new.audience := 'all'; new.created_by := auth.uid();
      new.members_count := 0; new.hidden := false;
    end if;
  else
    new.updated_at := now();
    if not public.can_manage_channel(old.id) then
      new.audience := old.audience; new.review_status := old.review_status;
      new.created_by := old.created_by; new.members_count := old.members_count; new.hidden := old.hidden;
      if (new.name, new.description, new.category, new.tags, new.icon_url)
         is distinct from (old.name, old.description, old.category, old.tags, old.icon_url) then
        new.review_status := 'pending';
      end if;
    end if;
  end if;
  return new;
end $$;
create trigger channels_guard before insert or update on public.channels
  for each row execute function private.channels_guard();

create table public.channel_members (
  channel_id uuid not null references public.channels(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (channel_id, user_id)
);
alter table public.channel_members enable row level security;
create policy cm_read on public.channel_members for select to authenticated
  using (user_id = auth.uid() or public.can_manage_channel(channel_id));
create policy cm_join on public.channel_members for insert to authenticated
  with check (user_id = auth.uid() and public.channel_visible(channel_id));
create policy cm_leave on public.channel_members for delete to authenticated using (user_id = auth.uid());

create or replace function private.members_count() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update public.channels set members_count = members_count + case when tg_op = 'INSERT' then 1 else -1 end
  where id = coalesce(new.channel_id, old.channel_id);
  return null;
end $$;
create trigger channel_members_count after insert or delete on public.channel_members
  for each row execute function private.members_count();

create table public.channel_folders (
  id uuid primary key default gen_random_uuid(),
  channel_id uuid not null references public.channels(id) on delete cascade,
  name text not null,
  position integer not null default 0
);
alter table public.channel_folders enable row level security;
create policy cf_read on public.channel_folders for select to anon, authenticated using (public.channel_visible(channel_id));
create policy cf_write on public.channel_folders for all to authenticated
  using (public.can_upload_channel(channel_id)) with check (public.can_upload_channel(channel_id));

create table public.blocked_channels (
  user_id uuid not null references auth.users(id) on delete cascade,
  channel_id uuid not null references public.channels(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, channel_id)
);
alter table public.blocked_channels enable row level security;
create policy bc_own on public.blocked_channels for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------- posts ----------
create table public.posts (
  id uuid primary key default gen_random_uuid(),
  channel_id uuid not null references public.channels(id) on delete cascade,
  folder_id uuid references public.channel_folders(id) on delete set null,
  title text not null check (length(title) between 1 and 200),
  description text,
  audience text not null default 'all' check (audience in ('all','organic','ads')),
  status text not null default 'draft' check (status in ('draft','published','scheduled')),
  publish_at timestamptz,
  hidden boolean not null default false,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);
create index on public.posts (channel_id, created_at desc);
create index on public.posts (created_at desc);
alter table public.posts enable row level security;

create or replace function public.post_visible(pid uuid, uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.posts p where p.id = pid and (
    public.can_upload_channel(p.channel_id, uid) or
    (not p.hidden and (p.status = 'published' or (p.status = 'scheduled' and p.publish_at <= now()))
     and public.can_see_audience(p.audience, uid) and public.channel_visible(p.channel_id, uid))))
$$;

create policy posts_read on public.posts for select to anon, authenticated using (public.post_visible(id));
create policy posts_write on public.posts for insert to authenticated with check (public.can_upload_channel(channel_id));
create policy posts_update on public.posts for update to authenticated
  using (public.can_upload_channel(channel_id)) with check (public.can_upload_channel(channel_id));
create policy posts_delete on public.posts for delete to authenticated using (public.can_upload_channel(channel_id));

create or replace function private.posts_guard() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then return new; end if;
  -- non-admin creators cannot set audience or unhide
  if not public.can_manage_channel(new.channel_id) then
    if tg_op = 'INSERT' then new.audience := 'all'; new.hidden := false; new.created_by := auth.uid();
    else new.audience := old.audience; new.hidden := old.hidden; end if;
  end if;
  return new;
end $$;
create trigger posts_guard before insert or update on public.posts
  for each row execute function private.posts_guard();

create table public.post_items (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  media_key text not null,
  thumbnail_key text,
  mime text,
  is_premium boolean not null default false,
  duration_s integer,
  trailer_key text,
  size_bytes bigint,
  position integer not null default 0
);
create index on public.post_items (post_id, position);
alter table public.post_items enable row level security;
create policy pi_read on public.post_items for select to anon, authenticated using (public.post_visible(post_id));
create policy pi_write on public.post_items for all to authenticated
  using (exists (select 1 from public.posts p where p.id = post_id and public.can_upload_channel(p.channel_id)))
  with check (exists (select 1 from public.posts p where p.id = post_id and public.can_upload_channel(p.channel_id)));

-- what the app should play for an item: full media or trailer (or nothing)
create or replace function public.playable_key(p_item_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select case
    when i.id is null or not public.post_visible(i.post_id) then null
    when not i.is_premium or public.has_full_access() then jsonb_build_object('key', i.media_key, 'kind', 'full')
    when i.trailer_key is not null then jsonb_build_object('key', i.trailer_key, 'kind', 'trailer')
    else jsonb_build_object('key', null, 'kind', 'locked') end
  from (select 1) x left join public.post_items i on i.id = p_item_id
$$;

create or replace function public.can_read_media(obj text, uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.is_admin(uid) or exists (
    select 1 from public.post_items i join public.posts p on p.id = i.post_id
    where (i.thumbnail_key = obj or i.trailer_key = obj
           or (i.media_key = obj and (not i.is_premium or public.has_full_access(uid))))
      and (public.post_visible(p.id, uid)))
$$;

-- ---------- reports / support ----------
create table public.support_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  kind text not null check (kind in ('report','deletion','in_app')),
  target_type text check (target_type in ('post','channel')),
  target_id uuid,
  reason text,
  details text check (length(details) <= 4000),
  email text,
  status text not null default 'open' check (status in ('open','closed')),
  created_at timestamptz not null default now()
);
alter table public.support_requests enable row level security;
create policy sr_read on public.support_requests for select to authenticated
  using (user_id = auth.uid() or public.is_owner());
create policy sr_owner_update on public.support_requests for update to authenticated
  using (public.is_owner()) with check (public.is_owner());

create or replace function public.report_content(p_target_type text, p_target_id uuid, p_reason text, p_details text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if p_reason not in ('Sexual/nude','Violence','Hate/harassment','Copyright','Spam/scam','Other') then
    raise exception 'bad reason'; end if;
  insert into public.support_requests (user_id, kind, target_type, target_id, reason, details)
  values (auth.uid(), 'report', p_target_type, p_target_id, p_reason, left(p_details, 4000)) returning id into v_id;
  return v_id;
end $$;

create or replace function public.submit_support_request(p_kind text, p_details text, p_email text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if p_kind not in ('deletion','in_app') then raise exception 'bad kind'; end if;
  insert into public.support_requests (user_id, kind, details, email)
  values (auth.uid(), p_kind, left(p_details, 4000), left(p_email, 200)) returning id into v_id;
  return v_id;
end $$;
grant execute on function public.submit_support_request(text, text, text) to anon, authenticated;

-- ---------- personal cloud ----------
create table public.cloud_folders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  parent_id uuid references public.cloud_folders(id) on delete cascade,
  name text not null check (length(name) between 1 and 200),
  created_at timestamptz not null default now()
);
alter table public.cloud_folders enable row level security;
create policy cfo_own on public.cloud_folders for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid() and public.is_member());

create table public.cloud_files (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  folder_id uuid references public.cloud_folders(id) on delete set null,
  name text not null check (length(name) between 1 and 255),
  storage_key text not null unique,
  size_bytes bigint not null check (size_bytes >= 0),
  mime text,
  created_at timestamptz not null default now()
);
create index on public.cloud_files (user_id, folder_id);
alter table public.cloud_files enable row level security;
create policy cfi_read on public.cloud_files for select to authenticated using (user_id = auth.uid());
create policy cfi_insert on public.cloud_files for insert to authenticated with check (
  user_id = auth.uid() and public.is_member()
  and storage_key like auth.uid()::text || '/%'
  and (select p.used_bytes from public.profiles p where p.id = auth.uid()) + size_bytes <= public.quota_bytes());
create policy cfi_update on public.cloud_files for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy cfi_delete on public.cloud_files for delete to authenticated using (user_id = auth.uid());

create or replace function private.cloud_files_guard() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  -- rename / move only
  new.size_bytes := old.size_bytes; new.storage_key := old.storage_key; new.user_id := old.user_id;
  return new;
end $$;
create trigger cloud_files_guard before update on public.cloud_files
  for each row execute function private.cloud_files_guard();

create or replace function private.cloud_used_bytes() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    update public.profiles set used_bytes = used_bytes + new.size_bytes where id = new.user_id;
  else
    update public.profiles set used_bytes = greatest(0, used_bytes - old.size_bytes) where id = old.user_id;
  end if;
  return null;
end $$;
create trigger cloud_files_used after insert or delete on public.cloud_files
  for each row execute function private.cloud_used_bytes();

-- ---------- storage ----------
insert into storage.buckets (id, name, public) values
  ('media','media',false), ('cloud','cloud',false), ('avatars','avatars',false),
  ('channel-icons','channel-icons',false), ('downloads','downloads',true)
on conflict (id) do nothing;

create policy media_read on storage.objects for select to anon, authenticated
  using (bucket_id = 'media' and public.can_read_media(name));
create policy media_write on storage.objects for insert to authenticated
  with check (bucket_id = 'media' and public.can_upload_channel(nullif((storage.foldername(name))[1],'')::uuid));
create policy media_delete on storage.objects for delete to authenticated
  using (bucket_id = 'media' and public.can_upload_channel(nullif((storage.foldername(name))[1],'')::uuid));

-- cloud: object exists only if a cloud_files row (quota-checked) owns it
create policy cloud_read on storage.objects for select to authenticated
  using (bucket_id = 'cloud' and (storage.foldername(name))[1] = auth.uid()::text);
create policy cloud_write on storage.objects for insert to authenticated
  with check (bucket_id = 'cloud' and (storage.foldername(name))[1] = auth.uid()::text
    and exists (select 1 from public.cloud_files f where f.storage_key = name and f.user_id = auth.uid()));
create policy cloud_delete on storage.objects for delete to authenticated
  using (bucket_id = 'cloud' and (storage.foldername(name))[1] = auth.uid()::text);

create policy avatars_read on storage.objects for select to authenticated using (bucket_id = 'avatars');
create policy avatars_write on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy avatars_update on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create policy icons_read on storage.objects for select to anon, authenticated using (bucket_id = 'channel-icons');
create policy icons_write on storage.objects for insert to authenticated
  with check (bucket_id = 'channel-icons' and (public.is_admin() or (storage.foldername(name))[1] = auth.uid()::text));

create policy downloads_owner_write on storage.objects for insert to authenticated
  with check (bucket_id = 'downloads' and public.is_owner());
create policy downloads_owner_update on storage.objects for update to authenticated
  using (bucket_id = 'downloads' and public.is_owner());
create policy downloads_owner_delete on storage.objects for delete to authenticated
  using (bucket_id = 'downloads' and public.is_owner());
