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
create function tests.as_service() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
end $$;
grant usage on schema tests to authenticated;
create table tests.o (k text primary key, id uuid, ref text);
grant all on tests.o to authenticated;

insert into auth.users (id, email, is_anonymous) values
  ('00000000-0000-0000-0000-0000000002a1', 'owner@x.test', false),
  ('00000000-0000-0000-0000-0000000002a2', 'org@x.test', false),
  ('00000000-0000-0000-0000-0000000002a3', 'other@x.test', false);
insert into admins (user_id, role) values ('00000000-0000-0000-0000-0000000002a1', 'owner');
insert into private.user_sources values ('00000000-0000-0000-0000-0000000002a2', 'organic'), ('00000000-0000-0000-0000-0000000002a3', 'organic');
update plans set active = false;
insert into plans (id, code, name, price_inr, duration_days) values
  ('00000000-0000-0000-0000-0000000002f1', 'p_monthly', 'Monthly', 118, 30),
  ('00000000-0000-0000-0000-0000000002f2', 'p_nop', 'Not on Play', 50, 30);
insert into play_products (product_id, plan_id, base_plan_id) values ('skykeep_monthly', '00000000-0000-0000-0000-0000000002f1', 'monthly');
update payment_settings set upi_id = 'shop@okaxis', payee_name = 'Shop';

-- ===== OFF by default =====
select tests.as_user('00000000-0000-0000-0000-0000000002a2');
select is(play_billing_on(), false, 'play billing is off by default');
select is(play_catalog(), '[]'::jsonb, 'no Play catalog while off');
select throws_ok($$ select create_play_choice_order('00000000-0000-0000-0000-0000000002f1', 'token-token-token', 'MH') $$,
  'play billing is off', 'no UCB orders while off');
select throws_ok($$ select play_record_purchase('00000000-0000-0000-0000-0000000002a2', 'skykeep_monthly', 't', 'GPA.1', 'SUBSCRIPTION_STATE_ACTIVE', now() + interval '30 days', true) $$,
  '42501', null, 'apps cannot record Play purchases themselves');
select is(length(play_account_id()), 64, 'obfuscated account id is a sha256 hex');
select isnt(play_account_id(), '00000000-0000-0000-0000-0000000002a2', 'obfuscated account id is not the raw user id');
reset role;

select tests.as_user('00000000-0000-0000-0000-0000000002a1');
select throws_ok($$ update play_settings set play_billing_enabled = true $$, '42501', null, 'cannot enable billing before Google approval');
update play_settings set google_approval_confirmed = true;
update play_settings set play_billing_enabled = true;
select is((select play_billing_enabled from play_settings), true, 'owner enables billing after confirming approval');
select ok((admin_play_overview() ->> 'products')::int = 1, 'owner sees Play overview');
reset role;
select tests.as_user('00000000-0000-0000-0000-0000000002a2');
select throws_ok($$ select admin_play_overview() $$, '42501', null, 'members cannot see Play overview');
select is((my_status() ->> 'play_billing_enabled')::boolean, true, 'my_status reports Play billing on');
select is(jsonb_array_length(play_catalog()), 1, 'catalog lists only plans mapped to a Play product');
select is(play_catalog() -> 0 ->> 'product_id', 'skykeep_monthly', 'catalog carries the product id');

-- ===== User Choice Billing → UPI path =====
select throws_ok($$ select create_play_choice_order('00000000-0000-0000-0000-0000000002f1', 'token-token-token', 'XX') $$, 'choose your state');
select throws_ok($$ select create_play_choice_order('00000000-0000-0000-0000-0000000002f1', 'short', 'MH') $$, 'missing external transaction token');
select throws_ok($$ select create_play_choice_order('00000000-0000-0000-0000-0000000002f2', 'token-token-token', 'MH') $$, 'plan not available on Google Play');
insert into tests.o select 'u', (j->>'order_id')::uuid, j->>'reference'
  from (select create_play_choice_order('00000000-0000-0000-0000-0000000002f1', 'ext-token-0001', 'mh') j) x;
select is((select count(*)::int from play_purchases where kind = 'alternative'), 1, 'external token stored with the order');
select is((select buyer_state from play_purchases where kind = 'alternative'), 'MH', 'buyer state stored');
select is(report_result((select id from tests.o where k = 'u'),
  'txnId=PLAYUPI1234&Status=SUCCESS&txnRef=' || (select ref from tests.o where k = 'u')) ->> 'status', 'review', 'UPI choice order verified by the normal rules');
reset role;
select tests.as_user('00000000-0000-0000-0000-0000000002a1');
select admin_approve_review((select id from tests.o where k = 'u'));
reset role;
select tests.as_service();
select is((select count(*)::int from play_pending_reports()), 1, 'paid UCB order waits for the Google report');
select is((select amount_paise from play_pending_reports()), 11800, 'report carries the paid amount');
select play_mark_report((select id from play_pending_reports()), false, 'boom');
select is((select report_attempts from play_purchases where kind = 'alternative'), 1, 'failed report counted');
select is((select count(*)::int from play_pending_reports()), 1, 'failed report retried');
select play_mark_report((select id from play_pending_reports()), true);
select is((select count(*)::int from play_pending_reports()), 0, 'reported once -> no longer pending');

-- ===== Google Play path =====
update subscriptions set status = 'revoked' where user_id = '00000000-0000-0000-0000-0000000002a3';
select is(play_record_purchase('00000000-0000-0000-0000-0000000002a3', 'skykeep_monthly', 'gp-token-1', 'GPA.1',
  'SUBSCRIPTION_STATE_ACTIVE', now() + interval '30 days', true) ->> 'active', 'true', 'verified purchase is active');
select is((select source || '/' || kind from subscriptions where user_id = '00000000-0000-0000-0000-0000000002a3' and status = 'active'),
  'google_play/play', 'subscription source google_play');
select is((select profiles.ads_access_status from profiles where id = '00000000-0000-0000-0000-0000000002a3'), 'pending', 'organic Play buyer -> access pending');
select play_record_purchase('00000000-0000-0000-0000-0000000002a3', 'skykeep_monthly', 'gp-token-1', 'GPA.1..0',
  'SUBSCRIPTION_STATE_ACTIVE', now() + interval '60 days', true);
select is((select count(*)::int from subscriptions where user_id = '00000000-0000-0000-0000-0000000002a3' and kind = 'play'), 1, 'renewal updates the same subscription');
select ok((select ends_at from subscriptions where user_id = '00000000-0000-0000-0000-0000000002a3' and kind = 'play') > now() + interval '59 days',
  'entitlement follows Google''s expiry');
select throws_ok($$ select play_record_purchase('00000000-0000-0000-0000-0000000002a2', 'skykeep_monthly', 'gp-token-1', 'GPA.1',
  'SUBSCRIPTION_STATE_ACTIVE', now() + interval '30 days', true) $$, 'purchase belongs to another account');
select throws_ok($$ select play_record_purchase('00000000-0000-0000-0000-0000000002a3', 'nope', 'gp-token-2', 'GPA.2',
  'SUBSCRIPTION_STATE_ACTIVE', now() + interval '30 days', true) $$, 'unknown play product nope');
reset role;
select tests.as_user('00000000-0000-0000-0000-0000000002a3');
select is((my_status() ->> 'is_premium')::boolean, true, 'Play subscriber is premium');
reset role;
select tests.as_service();
select play_record_purchase('00000000-0000-0000-0000-0000000002a3', 'skykeep_monthly', 'gp-token-1', 'GPA.1..0',
  'SUBSCRIPTION_STATE_EXPIRED', now() - interval '1 day', true);
select is(has_active_plan('00000000-0000-0000-0000-0000000002a3'), false, 'expired Play subscription ends entitlement');
select play_record_purchase('00000000-0000-0000-0000-0000000002a3', 'skykeep_monthly', 'gp-token-1', 'GPA.1..0',
  'SUBSCRIPTION_STATE_REVOKED', now() + interval '10 days', true);
select is((select status from subscriptions where user_id = '00000000-0000-0000-0000-0000000002a3' and kind = 'play'), 'revoked', 'refund/revoke revokes');
select is(play_record_purchase('00000000-0000-0000-0000-0000000002a2', 'skykeep_monthly', 'gp-token-3', 'GPA.3',
  'SUBSCRIPTION_STATE_PENDING', now() + interval '30 days', false) ->> 'active', 'false', 'pending purchase grants nothing');

select * from finish();
rollback;
