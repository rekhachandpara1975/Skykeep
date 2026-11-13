begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select plan(2);
create schema if not exists tests;
create or replace function tests.as_user(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', uid::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end $$;
grant usage on schema tests to authenticated, anon;

-- a creator with a personal cloud file and content uploaded to a channel they own (all set up as service role)
insert into auth.users (id, email, is_anonymous) values ('00000000-0000-0000-0000-0000000002a1', 'creator@x.test', false);
insert into private.user_sources (user_id, source) values ('00000000-0000-0000-0000-0000000002a1', 'organic');

insert into public.channels (id, name, created_by, review_status, audience)
  values ('00000000-0000-0000-0000-0000000002b1', 'Mine', '00000000-0000-0000-0000-0000000002a1', 'approved', 'all');
insert into public.posts (id, channel_id, title, status, created_by)
  values ('00000000-0000-0000-0000-0000000002c1', '00000000-0000-0000-0000-0000000002b1', 'Clip', 'published', '00000000-0000-0000-0000-0000000002a1');
insert into public.post_items (post_id, media_key, size_bytes) values
  ('00000000-0000-0000-0000-0000000002c1', 'm/clip.mp4', 1000),
  ('00000000-0000-0000-0000-0000000002c1', 'm/clip2.mp4', 2000);
insert into public.cloud_files (user_id, name, storage_key, size_bytes)
  values ('00000000-0000-0000-0000-0000000002a1', 'photo.jpg', '00000000-0000-0000-0000-0000000002a1/photo.jpg', 500);

select tests.as_user('00000000-0000-0000-0000-0000000002a1');
select is((my_status() ->> 'used_bytes')::bigint, 3500::bigint,
  'used_bytes counts personal cloud files (500) plus the creator''s channel uploads (1000+2000)');

-- another user's storage is unaffected by this creator's uploads
select tests.as_user('00000000-0000-0000-0000-000000000103');
select is((my_status() ->> 'used_bytes')::bigint, 0::bigint, 'a different user sees none of it');

select * from finish();
rollback;
