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
delete from channels;
-- docs/rules.md content table: every cell, for guest / organic / ads / admin, in paid and free mode

insert into auth.users (id, email, is_anonymous) values
  ('00000000-0000-0000-0000-000000000101', null, true),
  ('00000000-0000-0000-0000-000000000102', null, true),
  ('00000000-0000-0000-0000-000000000103', 'org@x.test', false),
  ('00000000-0000-0000-0000-000000000104', 'org_plan@x.test', false),
  ('00000000-0000-0000-0000-000000000105', 'org_approved@x.test', false),
  ('00000000-0000-0000-0000-000000000106', 'ads@x.test', false),
  ('00000000-0000-0000-0000-000000000107', 'ads_plan@x.test', false),
  ('00000000-0000-0000-0000-000000000108', 'admin@x.test', false);
insert into private.user_sources (user_id, source) values
  ('00000000-0000-0000-0000-000000000101', 'organic'),
  ('00000000-0000-0000-0000-000000000102', 'ads'),
  ('00000000-0000-0000-0000-000000000103', 'organic'),
  ('00000000-0000-0000-0000-000000000104', 'organic'),
  ('00000000-0000-0000-0000-000000000105', 'organic'),
  ('00000000-0000-0000-0000-000000000106', 'ads'),
  ('00000000-0000-0000-0000-000000000107', 'ads'),
  ('00000000-0000-0000-0000-000000000108', 'organic');
insert into public.admins (user_id, role) values ('00000000-0000-0000-0000-000000000108', 'owner');
update profiles set ads_access_status = 'approved' where id = '00000000-0000-0000-0000-000000000105';
insert into plans (id, code, name, price_inr, duration_days) values ('00000000-0000-0000-0000-0000000001f1', 'm1', 'Monthly', 99, 30);
insert into subscriptions (user_id, plan_id, kind, ends_at) values ('00000000-0000-0000-0000-000000000104', '00000000-0000-0000-0000-0000000001f1', 'paid', now() + interval '30 days');
insert into subscriptions (user_id, plan_id, kind, ends_at) values ('00000000-0000-0000-0000-000000000107', '00000000-0000-0000-0000-0000000001f1', 'paid', now() + interval '30 days');
select set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claims', '', true);
insert into channels (id, name, audience, review_status, status) values
  ('00000000-0000-0000-0000-0000000001c1', 'Main', 'all', 'approved', 'published');
insert into posts (id, channel_id, title, audience, status) values
  ('00000000-0000-0000-0000-0000000001d1', '00000000-0000-0000-0000-0000000001c1', 'all', 'all', 'published'),
  ('00000000-0000-0000-0000-0000000001d2', '00000000-0000-0000-0000-0000000001c1', 'org', 'organic', 'published'),
  ('00000000-0000-0000-0000-0000000001d3', '00000000-0000-0000-0000-0000000001c1', 'ads', 'ads', 'published');
insert into post_items (id, post_id, media_key, trailer_key, is_premium) values
  ('00000000-0000-0000-0000-0000000001e1', '00000000-0000-0000-0000-0000000001d1', 'm/prem.mp4', 'm/trailer.mp4', true),
  ('00000000-0000-0000-0000-0000000001e2', '00000000-0000-0000-0000-0000000001d1', 'm/free.mp4', null, false),
  ('00000000-0000-0000-0000-0000000001e3', '00000000-0000-0000-0000-0000000001d3', 'm/adsfree.mp4', null, false);


-- ===== paid mode =====
update app_mode set free_mode = false;
select tests.as_user('00000000-0000-0000-0000-000000000101');
select is((select string_agg(title, ',' order by title) from posts), 'all,org', 'paid: guest_org sees posts [all,org]');
select is((select count(*)::int from post_items), 2, 'paid: guest_org item count follows post visibility');
select is(playable_key('00000000-0000-0000-0000-0000000001e2') ->> 'kind', 'full', 'paid: guest_org free item plays in full');
select is(playable_key('00000000-0000-0000-0000-0000000001e1') ->> 'kind', 'trailer', 'paid: guest_org premium item -> trailer');
select is(can_read_media('m/prem.mp4'), false, 'paid: guest_org signed URL for full premium media refused');
select is(can_read_media('m/trailer.mp4'), true, 'paid: guest_org may read the trailer');
select is((can_view('00000000-0000-0000-0000-0000000001e1') ->> 'download')::boolean, false, 'paid: guest_org download refused');
select is(playable_key('00000000-0000-0000-0000-0000000001e3'), null, 'paid: guest_org gets nothing for hidden ads item');
select is(can_read_media('m/adsfree.mp4'), false, 'paid: guest_org no signed URL for hidden ads item');
select is((my_status() ->> 'is_premium')::boolean, false, 'paid: guest_org my_status.is_premium');
reset role;
select tests.as_user('00000000-0000-0000-0000-000000000102');
select is((select string_agg(title, ',' order by title) from posts), 'all', 'paid: guest_ads sees posts [all]');
select is((select count(*)::int from post_items), 2, 'paid: guest_ads item count follows post visibility');
select is(playable_key('00000000-0000-0000-0000-0000000001e2') ->> 'kind', 'full', 'paid: guest_ads free item plays in full');
select is(playable_key('00000000-0000-0000-0000-0000000001e1') ->> 'kind', 'trailer', 'paid: guest_ads premium item -> trailer');
select is(can_read_media('m/prem.mp4'), false, 'paid: guest_ads signed URL for full premium media refused');
select is(can_read_media('m/trailer.mp4'), true, 'paid: guest_ads may read the trailer');
select is((can_view('00000000-0000-0000-0000-0000000001e1') ->> 'download')::boolean, false, 'paid: guest_ads download refused');
select is(playable_key('00000000-0000-0000-0000-0000000001e3'), null, 'paid: guest_ads gets nothing for hidden ads item');
select is(can_read_media('m/adsfree.mp4'), false, 'paid: guest_ads no signed URL for hidden ads item');
select is((my_status() ->> 'is_premium')::boolean, false, 'paid: guest_ads my_status.is_premium');
reset role;
select tests.as_user('00000000-0000-0000-0000-000000000103');
select is((select string_agg(title, ',' order by title) from posts), 'all,org', 'paid: org sees posts [all,org]');
select is((select count(*)::int from post_items), 2, 'paid: org item count follows post visibility');
select is(playable_key('00000000-0000-0000-0000-0000000001e2') ->> 'kind', 'full', 'paid: org free item plays in full');
select is(playable_key('00000000-0000-0000-0000-0000000001e1') ->> 'kind', 'trailer', 'paid: org premium item -> trailer');
select is(playable_key('00000000-0000-0000-0000-0000000001e1') ->> 'key', 'm/trailer.mp4', 'paid: org without a plan never receives the full media key');
select is(can_read_media('m/prem.mp4'), false, 'paid: org signed URL for full premium media refused');
select is(can_read_media('m/trailer.mp4'), true, 'paid: org may read the trailer');
select is((can_view('00000000-0000-0000-0000-0000000001e1') ->> 'download')::boolean, false, 'paid: org download refused');
select is(playable_key('00000000-0000-0000-0000-0000000001e3'), null, 'paid: org gets nothing for hidden ads item');
select is(can_read_media('m/adsfree.mp4'), false, 'paid: org no signed URL for hidden ads item');
select is((my_status() ->> 'is_premium')::boolean, false, 'paid: org my_status.is_premium');
reset role;
select tests.as_user('00000000-0000-0000-0000-000000000104');
select is((select string_agg(title, ',' order by title) from posts), 'all,org', 'paid: org_plan sees posts [all,org]');
select is((select count(*)::int from post_items), 2, 'paid: org_plan item count follows post visibility');
select is(playable_key('00000000-0000-0000-0000-0000000001e2') ->> 'kind', 'full', 'paid: org_plan free item plays in full');
select is(playable_key('00000000-0000-0000-0000-0000000001e1') ->> 'kind', 'full', 'paid: org_plan premium item -> full');
select is(playable_key('00000000-0000-0000-0000-0000000001e1') ->> 'trailer_key', 'm/trailer.mp4', 'paid: org_plan gets the trailer to play before the full video');
select is(playable_key('00000000-0000-0000-0000-0000000001e2') ->> 'trailer_key', null, 'paid: org_plan item without trailer has no trailer_key');
select is(can_read_media('m/prem.mp4'), true, 'paid: org_plan signed URL for full premium media allowed');
select is(can_read_media('m/trailer.mp4'), true, 'paid: org_plan may read the trailer');
select is((can_view('00000000-0000-0000-0000-0000000001e1') ->> 'download')::boolean, true, 'paid: org_plan download allowed');
select is(playable_key('00000000-0000-0000-0000-0000000001e3'), null, 'paid: org_plan gets nothing for hidden ads item');
select is(can_read_media('m/adsfree.mp4'), false, 'paid: org_plan no signed URL for hidden ads item');
select is((my_status() ->> 'is_premium')::boolean, true, 'paid: org_plan my_status.is_premium');
reset role;
select tests.as_user('00000000-0000-0000-0000-000000000105');
select is((select string_agg(title, ',' order by title) from posts), 'all,org', 'paid: org_approved sees posts [all,org]');
select is((select count(*)::int from post_items), 2, 'paid: org_approved item count follows post visibility');
select is(playable_key('00000000-0000-0000-0000-0000000001e2') ->> 'kind', 'full', 'paid: org_approved free item plays in full');
select is(playable_key('00000000-0000-0000-0000-0000000001e1') ->> 'kind', 'trailer', 'paid: org_approved premium item -> trailer');
select is(can_read_media('m/prem.mp4'), false, 'paid: org_approved signed URL for full premium media refused');
select is(can_read_media('m/trailer.mp4'), true, 'paid: org_approved may read the trailer');
select is((can_view('00000000-0000-0000-0000-0000000001e1') ->> 'download')::boolean, false, 'paid: org_approved download refused');
select is(playable_key('00000000-0000-0000-0000-0000000001e3'), null, 'paid: org_approved gets nothing for hidden ads item');
select is(can_read_media('m/adsfree.mp4'), false, 'paid: org_approved no signed URL for hidden ads item');
select is((my_status() ->> 'is_premium')::boolean, false, 'paid: org_approved my_status.is_premium');
reset role;
select tests.as_user('00000000-0000-0000-0000-000000000106');
select is((select string_agg(title, ',' order by title) from posts), 'ads,all', 'paid: ads sees posts [ads,all]');
select is((select count(*)::int from post_items), 3, 'paid: ads item count follows post visibility');
select is(playable_key('00000000-0000-0000-0000-0000000001e2') ->> 'kind', 'full', 'paid: ads free item plays in full');
select is(playable_key('00000000-0000-0000-0000-0000000001e1') ->> 'kind', 'trailer', 'paid: ads premium item -> trailer');
select is(can_read_media('m/prem.mp4'), false, 'paid: ads signed URL for full premium media refused');
select is(can_read_media('m/trailer.mp4'), true, 'paid: ads may read the trailer');
select is((can_view('00000000-0000-0000-0000-0000000001e1') ->> 'download')::boolean, false, 'paid: ads download refused');
select is((my_status() ->> 'is_premium')::boolean, false, 'paid: ads my_status.is_premium');
reset role;
select tests.as_user('00000000-0000-0000-0000-000000000107');
select is((select string_agg(title, ',' order by title) from posts), 'ads,all', 'paid: ads_plan sees posts [ads,all]');
select is((select count(*)::int from post_items), 3, 'paid: ads_plan item count follows post visibility');
select is(playable_key('00000000-0000-0000-0000-0000000001e2') ->> 'kind', 'full', 'paid: ads_plan free item plays in full');
select is(playable_key('00000000-0000-0000-0000-0000000001e1') ->> 'kind', 'full', 'paid: ads_plan premium item -> full');
select is(can_read_media('m/prem.mp4'), true, 'paid: ads_plan signed URL for full premium media allowed');
select is(can_read_media('m/trailer.mp4'), true, 'paid: ads_plan may read the trailer');
select is((can_view('00000000-0000-0000-0000-0000000001e1') ->> 'download')::boolean, true, 'paid: ads_plan download allowed');
select is((my_status() ->> 'is_premium')::boolean, true, 'paid: ads_plan my_status.is_premium');
reset role;
select tests.as_user('00000000-0000-0000-0000-000000000108');
select is((select string_agg(title, ',' order by title) from posts), 'ads,all,org', 'paid: admin sees posts [ads,all,org]');
select is((select count(*)::int from post_items), 3, 'paid: admin item count follows post visibility');
select is(playable_key('00000000-0000-0000-0000-0000000001e2') ->> 'kind', 'full', 'paid: admin free item plays in full');
select is(playable_key('00000000-0000-0000-0000-0000000001e1') ->> 'kind', 'full', 'paid: admin premium item -> full');
select is(can_read_media('m/prem.mp4'), true, 'paid: admin signed URL for full premium media allowed');
select is(can_read_media('m/trailer.mp4'), true, 'paid: admin may read the trailer');
select is((can_view('00000000-0000-0000-0000-0000000001e1') ->> 'download')::boolean, true, 'paid: admin download allowed');
select is((my_status() ->> 'is_premium')::boolean, true, 'paid: admin my_status.is_premium');
reset role;

-- ===== free mode =====
update app_mode set free_mode = true;
select tests.as_user('00000000-0000-0000-0000-000000000101');
select is((select string_agg(title, ',' order by title) from posts), 'all,org', 'free: guest_org sees posts [all,org]');
select is((select count(*)::int from post_items), 2, 'free: guest_org item count follows post visibility');
select is(playable_key('00000000-0000-0000-0000-0000000001e2') ->> 'kind', 'full', 'free: guest_org free item plays in full');
select is(playable_key('00000000-0000-0000-0000-0000000001e1') ->> 'kind', 'trailer', 'free: guest_org premium item -> trailer');
select is(can_read_media('m/prem.mp4'), false, 'free: guest_org signed URL for full premium media refused');
select is(can_read_media('m/trailer.mp4'), true, 'free: guest_org may read the trailer');
select is((can_view('00000000-0000-0000-0000-0000000001e1') ->> 'download')::boolean, false, 'free: guest_org download refused');
select is(playable_key('00000000-0000-0000-0000-0000000001e3'), null, 'free: guest_org gets nothing for hidden ads item');
select is(can_read_media('m/adsfree.mp4'), false, 'free: guest_org no signed URL for hidden ads item');
select is((my_status() ->> 'is_premium')::boolean, false, 'free: guest_org my_status.is_premium');
reset role;
select tests.as_user('00000000-0000-0000-0000-000000000102');
select is((select string_agg(title, ',' order by title) from posts), 'all', 'free: guest_ads sees posts [all]');
select is((select count(*)::int from post_items), 2, 'free: guest_ads item count follows post visibility');
select is(playable_key('00000000-0000-0000-0000-0000000001e2') ->> 'kind', 'full', 'free: guest_ads free item plays in full');
select is(playable_key('00000000-0000-0000-0000-0000000001e1') ->> 'kind', 'trailer', 'free: guest_ads premium item -> trailer');
select is(can_read_media('m/prem.mp4'), false, 'free: guest_ads signed URL for full premium media refused');
select is(can_read_media('m/trailer.mp4'), true, 'free: guest_ads may read the trailer');
select is((can_view('00000000-0000-0000-0000-0000000001e1') ->> 'download')::boolean, false, 'free: guest_ads download refused');
select is(playable_key('00000000-0000-0000-0000-0000000001e3'), null, 'free: guest_ads gets nothing for hidden ads item');
select is(can_read_media('m/adsfree.mp4'), false, 'free: guest_ads no signed URL for hidden ads item');
select is((my_status() ->> 'is_premium')::boolean, false, 'free: guest_ads my_status.is_premium');
reset role;
select tests.as_user('00000000-0000-0000-0000-000000000103');
select is((select string_agg(title, ',' order by title) from posts), 'all,org', 'free: org sees posts [all,org]');
select is((select count(*)::int from post_items), 2, 'free: org item count follows post visibility');
select is(playable_key('00000000-0000-0000-0000-0000000001e2') ->> 'kind', 'full', 'free: org free item plays in full');
select is(playable_key('00000000-0000-0000-0000-0000000001e1') ->> 'kind', 'trailer', 'free: org premium item -> trailer');
select is(can_read_media('m/prem.mp4'), false, 'free: org signed URL for full premium media refused');
select is(can_read_media('m/trailer.mp4'), true, 'free: org may read the trailer');
select is((can_view('00000000-0000-0000-0000-0000000001e1') ->> 'download')::boolean, false, 'free: org download refused');
select is(playable_key('00000000-0000-0000-0000-0000000001e3'), null, 'free: org gets nothing for hidden ads item');
select is(can_read_media('m/adsfree.mp4'), false, 'free: org no signed URL for hidden ads item');
select is((my_status() ->> 'is_premium')::boolean, false, 'free: org my_status.is_premium');
reset role;
select tests.as_user('00000000-0000-0000-0000-000000000104');
select is((select string_agg(title, ',' order by title) from posts), 'all,org', 'free: org_plan sees posts [all,org]');
select is((select count(*)::int from post_items), 2, 'free: org_plan item count follows post visibility');
select is(playable_key('00000000-0000-0000-0000-0000000001e2') ->> 'kind', 'full', 'free: org_plan free item plays in full');
select is(playable_key('00000000-0000-0000-0000-0000000001e1') ->> 'kind', 'trailer', 'free: org_plan premium item -> trailer');
select is(can_read_media('m/prem.mp4'), false, 'free: org_plan signed URL for full premium media refused');
select is(can_read_media('m/trailer.mp4'), true, 'free: org_plan may read the trailer');
select is((can_view('00000000-0000-0000-0000-0000000001e1') ->> 'download')::boolean, false, 'free: org_plan download refused');
select is(playable_key('00000000-0000-0000-0000-0000000001e3'), null, 'free: org_plan gets nothing for hidden ads item');
select is(can_read_media('m/adsfree.mp4'), false, 'free: org_plan no signed URL for hidden ads item');
select is((my_status() ->> 'is_premium')::boolean, false, 'free: org_plan my_status.is_premium');
reset role;
select tests.as_user('00000000-0000-0000-0000-000000000105');
select is((select string_agg(title, ',' order by title) from posts), 'ads,all,org', 'free: org_approved sees posts [ads,all,org]');
select is((select count(*)::int from post_items), 3, 'free: org_approved item count follows post visibility');
select is(playable_key('00000000-0000-0000-0000-0000000001e2') ->> 'kind', 'full', 'free: org_approved free item plays in full');
select is(playable_key('00000000-0000-0000-0000-0000000001e1') ->> 'kind', 'full', 'free: org_approved premium item -> full');
select is(can_read_media('m/prem.mp4'), true, 'free: org_approved signed URL for full premium media allowed');
select is(can_read_media('m/trailer.mp4'), true, 'free: org_approved may read the trailer');
select is((can_view('00000000-0000-0000-0000-0000000001e1') ->> 'download')::boolean, true, 'free: org_approved download allowed');
select is((my_status() ->> 'is_premium')::boolean, true, 'free: org_approved my_status.is_premium');
reset role;
select tests.as_user('00000000-0000-0000-0000-000000000106');
select is((select string_agg(title, ',' order by title) from posts), 'ads,all', 'free: ads sees posts [ads,all]');
select is((select count(*)::int from post_items), 3, 'free: ads item count follows post visibility');
select is(playable_key('00000000-0000-0000-0000-0000000001e2') ->> 'kind', 'full', 'free: ads free item plays in full');
select is(playable_key('00000000-0000-0000-0000-0000000001e1') ->> 'kind', 'full', 'free: ads premium item -> full');
select is(can_read_media('m/prem.mp4'), true, 'free: ads signed URL for full premium media allowed');
select is(can_read_media('m/trailer.mp4'), true, 'free: ads may read the trailer');
select is((can_view('00000000-0000-0000-0000-0000000001e1') ->> 'download')::boolean, true, 'free: ads download allowed');
select is((my_status() ->> 'is_premium')::boolean, true, 'free: ads my_status.is_premium');
reset role;
select tests.as_user('00000000-0000-0000-0000-000000000107');
select is((select string_agg(title, ',' order by title) from posts), 'ads,all', 'free: ads_plan sees posts [ads,all]');
select is((select count(*)::int from post_items), 3, 'free: ads_plan item count follows post visibility');
select is(playable_key('00000000-0000-0000-0000-0000000001e2') ->> 'kind', 'full', 'free: ads_plan free item plays in full');
select is(playable_key('00000000-0000-0000-0000-0000000001e1') ->> 'kind', 'full', 'free: ads_plan premium item -> full');
select is(can_read_media('m/prem.mp4'), true, 'free: ads_plan signed URL for full premium media allowed');
select is(can_read_media('m/trailer.mp4'), true, 'free: ads_plan may read the trailer');
select is((can_view('00000000-0000-0000-0000-0000000001e1') ->> 'download')::boolean, true, 'free: ads_plan download allowed');
select is((my_status() ->> 'is_premium')::boolean, true, 'free: ads_plan my_status.is_premium');
reset role;
select tests.as_user('00000000-0000-0000-0000-000000000108');
select is((select string_agg(title, ',' order by title) from posts), 'ads,all,org', 'free: admin sees posts [ads,all,org]');
select is((select count(*)::int from post_items), 3, 'free: admin item count follows post visibility');
select is(playable_key('00000000-0000-0000-0000-0000000001e2') ->> 'kind', 'full', 'free: admin free item plays in full');
select is(playable_key('00000000-0000-0000-0000-0000000001e1') ->> 'kind', 'full', 'free: admin premium item -> full');
select is(can_read_media('m/prem.mp4'), true, 'free: admin signed URL for full premium media allowed');
select is(can_read_media('m/trailer.mp4'), true, 'free: admin may read the trailer');
select is((can_view('00000000-0000-0000-0000-0000000001e1') ->> 'download')::boolean, true, 'free: admin download allowed');
select is((my_status() ->> 'is_premium')::boolean, true, 'free: admin my_status.is_premium');
reset role;

-- ===== helpers answer only about yourself =====
update app_mode set free_mode = false;
select tests.as_user('00000000-0000-0000-0000-000000000103');
select is(source_of('00000000-0000-0000-0000-000000000106'), null, 'cannot read another user''s source');
select is(has_active_plan('00000000-0000-0000-0000-000000000107'), false, 'cannot probe another user''s plan');
select is(has_full_access('00000000-0000-0000-0000-000000000107'), false, 'cannot probe another user''s premium');
select is(quota_bytes('00000000-0000-0000-0000-000000000107'), 0::bigint, 'cannot probe another user''s quota');
select is(source_of(), 'organic', 'can read own source');
reset role;
select tests.as_user('00000000-0000-0000-0000-000000000108');
select is(source_of('00000000-0000-0000-0000-000000000106'), 'ads', 'admin can read any user''s source');
select is(has_active_plan('00000000-0000-0000-0000-000000000107'), true, 'admin can read any user''s plan');
reset role;

-- ===== subscriptions.source =====
select is((select source from subscriptions where user_id = '00000000-0000-0000-0000-000000000104'), 'upi_app', 'paid kind -> upi_app');
select tests.as_user('00000000-0000-0000-0000-000000000108');
select admin_grant_premium('00000000-0000-0000-0000-000000000103', '00000000-0000-0000-0000-0000000001f1', 7);
reset role;
select is((select source from subscriptions where user_id = '00000000-0000-0000-0000-000000000103'), 'admin', 'admin grant -> admin');
select throws_ok($$ insert into subscriptions (user_id, kind, source, ends_at) values ('00000000-0000-0000-0000-000000000103', 'paid', 'bogus', now()) $$, '23514', null, 'unknown source rejected');

select * from finish();
rollback;
