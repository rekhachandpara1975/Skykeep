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
-- order id holder (keeps state between statements)
create table tests.o (k text primary key, id uuid, ref text);
grant all on tests.o to authenticated;

insert into auth.users (id, email, is_anonymous) values
  ('00000000-0000-0000-0000-0000000000b1', 'owner@x.test', false),
  ('00000000-0000-0000-0000-0000000000b2', 'ads@x.test', false),
  ('00000000-0000-0000-0000-0000000000b3', 'org@x.test', false),
  ('00000000-0000-0000-0000-0000000000b4', null, true);
insert into admins (user_id, role) values ('00000000-0000-0000-0000-0000000000b1', 'owner');
insert into private.user_sources values ('00000000-0000-0000-0000-0000000000b2', 'ads'), ('00000000-0000-0000-0000-0000000000b3', 'organic');
insert into plans (id, code, name, price_inr, duration_days, position, free_eligible) values
  ('00000000-0000-0000-0000-0000000000f1', 't_monthly', 'Monthly', 99, 30, 1, true),
  ('00000000-0000-0000-0000-0000000000f2', 't_yearly', 'Yearly', 799, 365, 2, false);

-- seed plans out of the way (rolled back)
update plans set active = false where code not like 't\_%';

-- ===== plans rules =====
select throws_ok($$ update plans set code = 'x' where code = 't_monthly' $$, 'plan code is read-only');
select throws_ok($$ delete from plans where code = 't_monthly' $$, 'plans cannot be deleted; deactivate instead');
select ok((select count(*) from settings_audit where table_name = 'plans') > 0, 'plan changes audited');
select ok((select revision from plan_catalog) > 1, 'catalog revision bumped');

-- ===== payments unavailable without UPI =====
select tests.as_user('00000000-0000-0000-0000-0000000000b2');
select is((plan_offers() ->> 'payments_available')::boolean, false, 'no UPI id -> payments off');
select throws_ok($$ select create_order('00000000-0000-0000-0000-0000000000f1') $$, 'payments unavailable');
reset role;
select throws_ok($$ update payment_settings set upi_id = 'not-a-upi' $$, '23514', null, 'UPI format checked');
update payment_settings set upi_id = 'shop@okaxis', payee_name = 'SkyKeep Shop';
select tests.as_user('00000000-0000-0000-0000-0000000000b4');
select throws_ok($$ select create_order('00000000-0000-0000-0000-0000000000f1') $$, '42501', null, 'guest must log in to buy');
reset role;

-- ===== snapshot + happy path =====
select tests.as_user('00000000-0000-0000-0000-0000000000b2');
insert into tests.o select 'a', (j->>'order_id')::uuid, j->>'reference' from (select create_order('00000000-0000-0000-0000-0000000000f1') j) x;
select is((select amount_paise from payment_orders where id = (select id from tests.o where k='a')), 9900, 'amount snapshotted in paise');
select matches((select ref from tests.o where k='a'), '^SK[0-9]{8}[0-9A-F]{8}$', 'reference = SK + date + hex');
select is((select (create_order('00000000-0000-0000-0000-0000000000f1') ->> 'order_id')::uuid), (select id from tests.o where k='a'), 'double tap reuses pending order');
-- wrong reference
select is(report_result((select id from tests.o where k='a'), 'txnId=ABC123456&Status=SUCCESS&txnRef=WRONG') ->> 'status', 'pending', 'wrong txnRef stays pending');
reset role;
select is((select raw_response from payment_orders where id = (select id from tests.o where k='a')), 'txnId=ABC123456&Status=SUCCESS&txnRef=WRONG', 'raw saved first');
update payment_orders set status = 'pending' where id = (select id from tests.o where k='a');
select tests.as_user('00000000-0000-0000-0000-0000000000b2');
select is(report_result((select id from tests.o where k='a'),
  'txnId=ABC123456&responseCode=00&Status=SUCCESS&txnRef=' || (select ref from tests.o where k='a')) ->> 'status', 'paid', 'valid SUCCESS activates');
select is(report_result((select id from tests.o where k='a'),
  'txnId=ABC123456&Status=SUCCESS&txnRef=' || (select ref from tests.o where k='a')) ->> 'status', 'paid', 'double report is idempotent');
select is((select count(*)::int from subscriptions), 1, 'exactly one subscription per order');
select is((my_status() ->> 'is_premium')::boolean, true, 'ads buyer is premium');
select is((my_status() ->> 'quota_bytes')::bigint, 2199023255552::bigint, 'plan -> 2 TB');

-- reused txn id
insert into tests.o select 'b', (j->>'order_id')::uuid, j->>'reference' from (select create_order('00000000-0000-0000-0000-0000000000f2') j) x;
select is(report_result((select id from tests.o where k='b'),
  'txnid=abc123456&status=success&txnref=' || (select ref from tests.o where k='b')) ->> 'status', 'pending', 'reused txn id rejected (case-insensitive)');
reset role;

-- old order (> 2 h)
select tests.as_user('00000000-0000-0000-0000-0000000000b2');
insert into tests.o select 'c', (j->>'order_id')::uuid, j->>'reference' from (select create_order('00000000-0000-0000-0000-0000000000f2') j) x;
reset role;
select isnt((select id from tests.o where k='c'), (select id from tests.o where k='b'), 'submitted-success order not reused, new order made');
select is((select status from payment_orders where id = (select id from tests.o where k='b')), 'submitted', 'order that reported SUCCESS is never auto-cancelled');
update payment_orders set created_at = now() - interval '3 hours' where id = (select id from tests.o where k='c');
select tests.as_user('00000000-0000-0000-0000-0000000000b2');
select is(report_result((select id from tests.o where k='c'),
  'txnId=OLD9999999&Status=SUCCESS&txnRef=' || (select ref from tests.o where k='c')) ->> 'status', 'pending', 'order older than 2h not auto-activated');
reset role;

-- FAILURE
select tests.as_user('00000000-0000-0000-0000-0000000000b2');
insert into tests.o select 'd', (j->>'order_id')::uuid, j->>'reference' from (select create_order('00000000-0000-0000-0000-0000000000f2') j) x;
select is(report_result((select id from tests.o where k='d'), 'Status=FAILURE&txnRef=' || (select ref from tests.o where k='d')) ->> 'status', 'failed', 'FAILURE -> failed');
-- garbage
insert into tests.o select 'e', (j->>'order_id')::uuid, j->>'reference' from (select create_order('00000000-0000-0000-0000-0000000000f2') j) x;
select is(report_result((select id from tests.o where k='e'), 'garbage') ->> 'status', 'pending', 'garbage stays pending');
reset role;

-- price change applies to new orders only + cancels repriced pending
update plans set price_inr = 899 where code = 't_yearly';
select tests.as_user('00000000-0000-0000-0000-0000000000b2');
insert into tests.o select 'f', (j->>'order_id')::uuid, j->>'reference' from (select create_order('00000000-0000-0000-0000-0000000000f2') j) x;
select is((select amount_paise from payment_orders where id = (select id from tests.o where k='f')), 89900, 'new order uses new price');
select is((select status from payment_orders where id = (select id from tests.o where k='e')), 'cancelled', 'repriced pending order cancelled');
select is((select ends_at::date from subscriptions limit 1), (now() + interval '30 days')::date, 'existing subscription keeps its end date');
reset role;

-- manual mode -> review
update payment_settings set activation_mode = 'manual';
select tests.as_user('00000000-0000-0000-0000-0000000000b2');
select is(report_result((select id from tests.o where k='f'),
  'txnId=MAN1234567&Status=SUCCESS&txnRef=' || (select ref from tests.o where k='f')) ->> 'status', 'review', 'manual mode -> review');
reset role;
select tests.as_user('00000000-0000-0000-0000-0000000000b1');
select admin_approve_review((select id from tests.o where k='f'));
select is((select status from payment_orders where id = (select id from tests.o where k='f')), 'paid', 'owner approves review');
select is((select ends_at::date from subscriptions where order_id = (select id from tests.o where k='f')), (now() + interval '395 days')::date, 'stacks on current end date');
select throws_ok($$ select admin_mark_paid((select id from tests.o where k='d'), '123') $$, 'UTR must be 12 digits');
select lives_ok($$ select admin_mark_paid((select id from tests.o where k='d'), '123456789012') $$, 'mark paid with 12-digit UTR');
select lives_ok($$ select admin_confirm_bank((select id from tests.o where k='d')) $$, 'bank verified');
select lives_ok($$ select admin_revoke_order((select id from tests.o where k='d')) $$, 'revoke');
select is((select status from subscriptions where order_id = (select id from tests.o where k='d')), 'revoked', 'revoke ends subscription');
reset role;
update payment_settings set activation_mode = 'instant';

-- daily cap: 3 automatic activations per user per 24h -> review
update payment_orders set auto_activated = true, paid_at = now() where id in (select id from tests.o where k in ('a','f'));
update payment_orders set auto_activated = true where id = (select id from tests.o where k = 'd');
select tests.as_user('00000000-0000-0000-0000-0000000000b2');
insert into tests.o select 'g', (j->>'order_id')::uuid, j->>'reference' from (select create_order('00000000-0000-0000-0000-0000000000f1') j) x;
select is(report_result((select id from tests.o where k='g'),
  'txnId=CAP1234567&Status=SUCCESS&txnRef=' || (select ref from tests.o where k='g')) ->> 'status', 'review', '>=3 auto activations in 24h -> review');
reset role;

-- UPI change cancels old pending; clear turns payments off
select tests.as_user('00000000-0000-0000-0000-0000000000b3');
insert into tests.o select 'h', (j->>'order_id')::uuid, j->>'reference' from (select create_order('00000000-0000-0000-0000-0000000000f2') j) x;
reset role;
update payment_settings set upi_id = 'new@okhdfc';
select tests.as_user('00000000-0000-0000-0000-0000000000b3');
select is(create_order('00000000-0000-0000-0000-0000000000f2') ->> 'upi_id', 'new@okhdfc', 'new orders go to new UPI id');
select is((select status from payment_orders where id = (select id from tests.o where k='h')), 'cancelled', 'old-UPI pending order cancelled');
reset role;
update payment_settings set upi_id = '';
select is((select upi_id from payment_settings), null, 'empty UPI id stored as null');
select is(payments_available(), false, 'cleared UPI -> payments off');
update payment_settings set upi_id = 'new@okhdfc';

-- organic buyer needs approval for full access
update payment_orders set status = 'pending' where id = (select id from payment_orders where user_id = '00000000-0000-0000-0000-0000000000b3' and status = 'pending' limit 1);
select tests.as_user('00000000-0000-0000-0000-0000000000b3');
insert into tests.o select 'i', (j->>'order_id')::uuid, j->>'reference' from (select create_order('00000000-0000-0000-0000-0000000000f2') j) x;
select is(report_result((select id from tests.o where k='i'),
  'txnId=ORG1234567&Status=SUCCESS&txnRef=' || (select ref from tests.o where k='i')) ->> 'status', 'paid', 'organic buyer paid');
select is(my_status() ->> 'access_status', 'pending', 'organic buyer -> access pending');
select is((my_status() ->> 'is_premium')::boolean, false, 'organic buyer not premium until approved');
reset role;
select tests.as_user('00000000-0000-0000-0000-0000000000b1');
select admin_set_access('00000000-0000-0000-0000-0000000000b3', 'approved');
reset role;
select tests.as_user('00000000-0000-0000-0000-0000000000b3');
select is((my_status() ->> 'is_premium')::boolean, true, 'approved organic buyer is premium');
reset role;

-- ===== free plans per group =====
insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000b5', 'org3@x.test'), ('00000000-0000-0000-0000-0000000000b6', 'ads3@x.test');
insert into private.user_sources values ('00000000-0000-0000-0000-0000000000b5', 'organic'), ('00000000-0000-0000-0000-0000000000b6', 'ads');
update app_mode set free_plans_for = 'organic';
select isnt((select promo_id from app_mode), null, 'promotion id created');
select tests.as_user('00000000-0000-0000-0000-0000000000b6');
select is(plan_offers() -> 'free_plan_ids', '[]'::jsonb, 'ads user gets no free plans when organic-only');
select throws_ok($$ select claim_free_plan('00000000-0000-0000-0000-0000000000f1') $$, 'plan is not free for you');
reset role;
select tests.as_user('00000000-0000-0000-0000-0000000000b5');
select is(plan_offers() -> 'free_plan_ids', '["00000000-0000-0000-0000-0000000000f1"]'::jsonb, 'organic user sees free plan');
select throws_ok($$ select create_order('00000000-0000-0000-0000-0000000000f1') $$, 'plan is free for you; claim it instead');
select lives_ok($$ select claim_free_plan('00000000-0000-0000-0000-0000000000f1') $$, 'claim free plan');
select throws_ok($$ select claim_free_plan('00000000-0000-0000-0000-0000000000f1') $$, 'you already have an active plan');
select is((select count(*)::int from payment_orders where user_id = '00000000-0000-0000-0000-0000000000b5'), 0, 'free claim creates no payment order');
reset role;
update app_mode set free_plans_for = 'everyone';
select tests.as_user('00000000-0000-0000-0000-0000000000b6');
select is(jsonb_array_length(plan_offers() -> 'free_plan_ids'), 1, 'everyone -> ads user gets free plan');
reset role;
update app_mode set free_plans_for = 'none';

-- ===== plans visibility per group =====
update app_mode set plans_visible_for = 'ads';
select tests.as_user('00000000-0000-0000-0000-0000000000b5');
select is((my_status() ->> 'plans_visible')::boolean, false, 'organic hidden when ads-only');
select is(my_status() ->> 'plan_name', 'Monthly', 'existing subscriber still sees plan');
select throws_ok($$ select create_order('00000000-0000-0000-0000-0000000000f2') $$, 'plans not available');
reset role;
select tests.as_user('00000000-0000-0000-0000-0000000000b6');
select is((my_status() ->> 'plans_visible')::boolean, true, 'ads user sees plans');
reset role;
update app_mode set plans_visible_for = 'none', free_plans_for = 'everyone';
select tests.as_user('00000000-0000-0000-0000-0000000000b6');
select is(plan_offers() -> 'free_plan_ids', '[]'::jsonb, 'hidden plans are never free');
reset role;
select tests.as_user('00000000-0000-0000-0000-0000000000b1');
select is((my_status() ->> 'plans_visible')::boolean, true, 'admins always see plans');
reset role;

-- stale cron
update payment_orders set created_at = now() - interval '25 hours' where status = 'pending';
select ok(private.cancel_stale_orders() >= 0, 'stale cancel runs');
select is((select count(*)::int from payment_orders where status = 'pending' and created_at < now() - interval '24 hours'), 0, 'stale pending cancelled');

select * from finish();
rollback;
