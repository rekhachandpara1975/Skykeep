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
grant usage on schema tests to authenticated;
create table tests.o (k text primary key, id uuid, ref text);
grant all on tests.o to authenticated;

-- a guest from ads (automatic anonymous login on first open)
insert into auth.users (id, is_anonymous) values ('00000000-0000-0000-0000-00000000a0a1', true);
insert into private.user_sources values ('00000000-0000-0000-0000-00000000a0a1', 'ads') on conflict (user_id) do update set source = 'ads';
update plans set active = false where true;
insert into plans (id, code, name, price_inr, duration_days) values ('00000000-0000-0000-0000-00000000a0f1', 'g_trial', 'Trial', 69, 2);
update payment_settings set upi_id = '2728412a@bandhan', payee_name = 'As Enterprice', activation_mode = 'instant' where true;
update app_mode set free_mode = false, plans_visible_for = 'everyone' where true;

select tests.as_user('00000000-0000-0000-0000-00000000a0a1');
select is((my_status() ->> 'is_guest')::boolean, true, 'guest');
select ok(plans_visible_for_me(), 'guest sees plans');
insert into tests.o select 'a', (j->>'order_id')::uuid, j->>'reference' from (select create_order('00000000-0000-0000-0000-00000000a0f1') j) x;
select is(report_result((select id from tests.o where k='a'),
  'ApprovalRefNo=711122223333&Status=SUCCESS&txnRef=' || (select ref from tests.o where k='a')) ->> 'status', 'paid', 'guest pays');
select ok(has_full_access(), 'paying guest gets full videos');
select ok(has_ads_access(), 'paying ads guest sees ads content');
select is(quota_bytes(), 2199023255552::bigint, 'paying guest gets 2 TB');
reset role;

-- guest adds an email later: same account, plan stays
update auth.users set is_anonymous = false, email = 'buyer@x.test' where id = '00000000-0000-0000-0000-00000000a0a1';
select tests.as_user('00000000-0000-0000-0000-00000000a0a1');
select is((my_status() ->> 'is_guest')::boolean, false, 'now a member');
select ok(has_plan(), 'plan kept after adding email');
reset role;

-- a guest without a plan still has no full access
insert into auth.users (id, is_anonymous) values ('00000000-0000-0000-0000-00000000a0a2', true);
select tests.as_user('00000000-0000-0000-0000-00000000a0a2');
select ok(not has_full_access(), 'non-paying guest: no full access');
select is(quota_bytes(), 0::bigint, 'non-paying guest: no storage');
reset role;

select * from finish();
rollback;
