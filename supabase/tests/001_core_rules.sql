begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select no_plan();

create schema tests;
create function tests.as_user(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', uid::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end $$;
grant usage on schema tests to authenticated, anon;

-- ignore seed data (rolled back)
delete from channels;

-- users: owner, ads member, organic member, guest, second organic member
insert into auth.users (id, email, is_anonymous) values
  ('00000000-0000-0000-0000-0000000000a1', 'owner@x.test', false),
  ('00000000-0000-0000-0000-0000000000a2', 'ads@x.test', false),
  ('00000000-0000-0000-0000-0000000000a3', 'org@x.test', false),
  ('00000000-0000-0000-0000-0000000000a4', null, true),
  ('00000000-0000-0000-0000-0000000000a5', 'org2@x.test', false);
insert into public.admins (user_id, role) values ('00000000-0000-0000-0000-0000000000a1', 'owner');

-- ===== accounts =====
select is((select is_guest from profiles where id = '00000000-0000-0000-0000-0000000000a4'), true, 'anonymous user gets guest profile');
select is((select count(*)::int from profiles), 5, 'profile per auth user');

-- ===== attribution =====
select tests.as_user('00000000-0000-0000-0000-0000000000a2');
select is(record_install('install-ads-0001', 'ok', 'utm_source=Instagram&utm_campaign=apk_download', 'secret-secret-secret-1'), 'ads', 'instagram referrer -> ads');
select is(record_install('install-ads-0001', 'ok', 'utm_source=google', 'secret-secret-secret-1'), 'ads', 'second call keeps first touch');
select throws_ok($$ select record_install('install-ads-0001', 'ok', '', 'wrong-secret-wrong-secret') $$, 'install secret mismatch');
reset role;
select tests.as_user('00000000-0000-0000-0000-0000000000a3');
select is(record_install('install-org-0001', 'ok', 'utm_source=google-play', 'secret-secret-secret-2'), 'organic', 'other referrer -> organic');
reset role;
select tests.as_user('00000000-0000-0000-0000-0000000000a5');
select is(record_install('install-org-0002', 'ok', null, 'secret-secret-secret-3'), 'organic', 'no referrer -> organic');
reset role;
select tests.as_user('00000000-0000-0000-0000-0000000000a4');
select is(record_install('install-ads-0002', 'ok', 'utm_source=meta', 'secret-secret-secret-4'), 'ads', 'guest from meta -> ads');
reset role;
select throws_ok($$ update private.user_sources set source = 'organic' where user_id = '00000000-0000-0000-0000-0000000000a2' $$,
  'user source is immutable', 'source cannot change, even as superuser');
select throws_ok($$ delete from private.user_sources where user_id = '00000000-0000-0000-0000-0000000000a2' $$,
  'user source is immutable', 'source cannot be deleted');
update auth.users set is_anonymous = false, email = 'guest@x.test' where id = '00000000-0000-0000-0000-0000000000a4';
select is((select is_guest from profiles where id = '00000000-0000-0000-0000-0000000000a4'), false, 'guest conversion flips is_guest');
select is(source_of('00000000-0000-0000-0000-0000000000a4'), 'ads', 'guest conversion keeps source');

-- ===== channels / audience =====
select set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claims', '', true); -- act as service role for fixtures
insert into channels (id, name, audience, review_status, status) values
  ('00000000-0000-0000-0000-00000000c001', 'All channel', 'all', 'approved', 'published'),
  ('00000000-0000-0000-0000-00000000c002', 'Organic channel', 'organic', 'approved', 'published'),
  ('00000000-0000-0000-0000-00000000c003', 'Ads channel', 'ads', 'approved', 'published');
insert into posts (id, channel_id, title, audience, status) values
  ('00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-00000000c001', 'p all', 'all', 'published'),
  ('00000000-0000-0000-0000-00000000d002', '00000000-0000-0000-0000-00000000c001', 'p ads', 'ads', 'published'),
  ('00000000-0000-0000-0000-00000000d003', '00000000-0000-0000-0000-00000000c001', 'p draft', 'all', 'draft');
insert into post_items (id, post_id, media_key, trailer_key, is_premium) values
  ('00000000-0000-0000-0000-00000000e001', '00000000-0000-0000-0000-00000000d001', 'c001/full.mp4', 'c001/trailer.mp4', true);

select tests.as_user('00000000-0000-0000-0000-0000000000a3');
select is((select count(*)::int from channels), 2, 'organic user sees all + organic channels');
select is((select count(*)::int from posts), 1, 'organic user sees only published all-audience post');
select is(playable_key('00000000-0000-0000-0000-00000000e001') ->> 'kind', 'trailer', 'non-premium gets trailer');
reset role;
select tests.as_user('00000000-0000-0000-0000-0000000000a2');
select is((select count(*)::int from channels), 2, 'ads user sees all + ads channels');
select is((select count(*)::int from posts), 2, 'ads user sees ads post');
reset role;
select set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claims', '', true);
set local role anon;
select is((select count(*)::int from channels), 1, 'anon sees only all-audience channels');
reset role;

-- ===== channel approval =====
select tests.as_user('00000000-0000-0000-0000-0000000000a3');
select throws_ok($$ insert into channels (name) values ('No consent') $$, '42501', null, 'consent required before creating channel');
insert into consents (user_id, policy_version) values ('00000000-0000-0000-0000-0000000000a3', '2026-11');
insert into channels (id, name, description, audience, review_status) values
  ('00000000-0000-0000-0000-00000000c010', 'My channel', 'desc', 'ads', 'approved');
select is((select review_status || '/' || audience from channels where id = '00000000-0000-0000-0000-00000000c010'), 'pending/all', 'user channel starts pending, cannot choose audience');
select throws_ok($$ insert into posts (channel_id, title) values ('00000000-0000-0000-0000-00000000c010', 'x') $$, '42501', null, 'no upload while pending');
reset role;
select tests.as_user('00000000-0000-0000-0000-0000000000a5');
select is((select count(*)::int from channels where id = '00000000-0000-0000-0000-00000000c010'), 0, 'pending channel hidden from others');
select throws_ok($$ select admin_review_channel('00000000-0000-0000-0000-00000000c010', true, 'all') $$, '42501', null, 'non-owner cannot approve');
reset role;
select tests.as_user('00000000-0000-0000-0000-0000000000a1');
select admin_review_channel('00000000-0000-0000-0000-00000000c010', true, 'organic');
reset role;
select tests.as_user('00000000-0000-0000-0000-0000000000a3');
select lives_ok($$ insert into posts (channel_id, title, status) values ('00000000-0000-0000-0000-00000000c010', 'mine', 'published') $$, 'creator uploads to own approved channel');
select throws_ok($$ insert into posts (channel_id, title) values ('00000000-0000-0000-0000-00000000c001', 'x') $$, '42501', null, 'cannot upload to someone else''s channel');
update channels set description = 'changed' where id = '00000000-0000-0000-0000-00000000c010';
select is((select review_status from channels where id = '00000000-0000-0000-0000-00000000c010'), 'pending', 'descriptive edit goes back to pending');
reset role;
select tests.as_user('00000000-0000-0000-0000-0000000000a1');
insert into channels (name) values ('Admin made');
select is((select review_status from channels where name = 'Admin made'), 'approved', 'admin-created channel approved immediately');
reset role;

-- ===== quota =====
select is(quota_bytes('00000000-0000-0000-0000-0000000000a3'), 0::bigint, 'paid mode, no plan -> 0');
update app_mode set free_mode = true;
select is(quota_bytes('00000000-0000-0000-0000-0000000000a3'), 16106127360::bigint, 'free mode member -> 15 GB');
insert into auth.users (id, is_anonymous) values ('00000000-0000-0000-0000-0000000000a9', true);
select is(quota_bytes('00000000-0000-0000-0000-0000000000a9'), 0::bigint, 'guest -> 0 even in free mode');
select tests.as_user('00000000-0000-0000-0000-0000000000a3');
select lives_ok($$ insert into cloud_files (name, storage_key, size_bytes) values ('a.jpg', '00000000-0000-0000-0000-0000000000a3/a.jpg', 1000) $$, 'upload within quota');
select is((select used_bytes from profiles where id = '00000000-0000-0000-0000-0000000000a3'), 1000::bigint, 'used_bytes kept by trigger');
select throws_ok($$ insert into cloud_files (name, storage_key, size_bytes) values ('b.bin', '00000000-0000-0000-0000-0000000000a3/b.bin', 16106127360) $$, '42501', null, 'over quota blocked by RLS');
-- free mode: organic member requests full access
select is(request_full_access(), 'pending', 'organic request full access -> pending');
select throws_ok($$ select create_order(gen_random_uuid()) $$, 'payments are off in free mode');
select is((my_status() ->> 'plans_visible')::boolean, false, 'no plans in free mode');
reset role;
select tests.as_user('00000000-0000-0000-0000-0000000000a2');
select is((my_status() ->> 'is_premium')::boolean, true, 'ads users get full access in free mode');
reset role;
update app_mode set free_mode = false;
update profiles set ads_access_status = 'none' where id = '00000000-0000-0000-0000-0000000000a3';

-- ===== admin-only =====
select tests.as_user('00000000-0000-0000-0000-0000000000a2');
select throws_ok($$ select admin_stats() $$, '42501', null, 'members cannot read admin stats');
select is((select count(*)::int from payment_settings), 0, 'members cannot read payment settings');
select throws_ok($$ select * from admin_users() $$, '42501', null, 'members cannot list users');
reset role;

select * from finish();
rollback;
