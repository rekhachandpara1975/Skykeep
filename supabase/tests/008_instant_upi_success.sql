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
create function tests.st(k text) returns text language sql as $$ select status from public.payment_orders where id = (select id from tests.o where tests.o.k = st.k) $$;
create function tests.new_order(k text, plan uuid) returns void language sql as $$
  insert into tests.o select k, (j->>'order_id')::uuid, j->>'reference' from (select public.create_order(plan) j) x $$;
grant execute on all functions in schema tests to authenticated;

insert into auth.users (id, email, is_anonymous) values
  ('00000000-0000-0000-0000-0000000008a1', 'i1@x.test', false),
  ('00000000-0000-0000-0000-0000000008a2', 'i2@x.test', false),
  ('00000000-0000-0000-0000-0000000008a3', 'owner8@x.test', false);
insert into admins (user_id, role) values ('00000000-0000-0000-0000-0000000008a3', 'owner');
insert into private.user_sources values ('00000000-0000-0000-0000-0000000008a1', 'ads'), ('00000000-0000-0000-0000-0000000008a2', 'ads');
update plans set active = false where true;
insert into plans (id, code, name, price_inr, duration_days) values
  ('00000000-0000-0000-0000-0000000008f1', 'i_trial', 'Trial', 69, 2),
  ('00000000-0000-0000-0000-0000000008f2', 'i_gold', 'Gold', 259, 30);
update payment_settings set upi_id = '2728412a@bandhan', payee_name = 'As Enterprice' where true;

select is((select activation_mode from payment_settings), 'instant', 'instant activation is the default');

-- ===== SUCCESS for this order → plan active at once =====
select tests.as_user('00000000-0000-0000-0000-0000000008a1');
select tests.new_order('a', '00000000-0000-0000-0000-0000000008f1');
select is(report_result((select id from tests.o where k='a'),
  'txnId=PHN0001&ApprovalRefNo=512233445566&responseCode=00&Status=SUCCESS&txnRef=' || (select ref from tests.o where k='a')) ->> 'status',
  'paid', 'UPI app SUCCESS -> plan active');
select ok(has_plan('00000000-0000-0000-0000-0000000008a1'), 'buyer has the plan');
reset role;
select is((select utr from payment_orders where id = (select id from tests.o where k='a')), '512233445566', '12-digit bank ref saved as UTR');
select is((select source from subscriptions where order_id = (select id from tests.o where k='a')), 'upi_app', 'source upi_app');
select ok((select auto_activated and not bank_verified from payment_orders where id = (select id from tests.o where k='a')),
  'shows in "activated today — verify against bank"');
select is((select count(*)::int from payment_order_events where order_id = (select id from tests.o where k='a') and new_status = 'paid'), 1, 'logged');

-- same answer again does nothing more
select tests.as_user('00000000-0000-0000-0000-0000000008a1');
select is(report_result((select id from tests.o where k='a'),
  'txnId=PHN0001&ApprovalRefNo=512233445566&Status=SUCCESS&txnRef=' || (select ref from tests.o where k='a')) ->> 'status', 'paid', 'repeat is harmless');
reset role;
select is((select count(*)::int from subscriptions where order_id = (select id from tests.o where k='a')), 1, 'one subscription');

-- ===== replaying someone's transaction id on another order → not activated =====
select tests.as_user('00000000-0000-0000-0000-0000000008a2');
select tests.new_order('b', '00000000-0000-0000-0000-0000000008f1');
select is(report_result((select id from tests.o where k='b'),
  'txnId=PHN0001&ApprovalRefNo=512233445566&Status=SUCCESS&txnRef=' || (select ref from tests.o where k='b')) ->> 'status',
  'pending', 'reused UTR never activates');
-- wrong order reference → not activated
select is(report_result((select id from tests.o where k='b'),
  'ApprovalRefNo=599988887777&Status=SUCCESS&txnRef=SOMETHINGELSE') ->> 'status', 'pending', 'other order''s reference never activates');
-- no transaction id → not activated
select is(report_result((select id from tests.o where k='b'), 'Status=SUCCESS&txnRef=' || (select ref from tests.o where k='b')) ->> 'status',
  'pending', 'SUCCESS without a transaction id never activates');
select ok(not has_plan('00000000-0000-0000-0000-0000000008a2'), 'still no plan');
-- FAILURE → failed
select tests.new_order('c', '00000000-0000-0000-0000-0000000008f2');
select is(report_result((select id from tests.o where k='c'), 'Status=FAILURE&txnRef=' || (select ref from tests.o where k='c')) ->> 'status', 'failed', 'FAILURE -> failed');
-- cancelled → waiting
select tests.new_order('d', '00000000-0000-0000-0000-0000000008f2');
select is(report_result((select id from tests.o where k='d'), '') ->> 'status', 'pending', 'cancelled -> still waiting');
reset role;

-- ===== bank SMS later confirms the instant activation, and never pays a different order =====
select is(bank_credit_received('512233445566', 6900, 'Rs 69 credited UPI Ref 512233445566') ->> 'result', 'confirmed', 'bank SMS confirms it');
select ok((select bank_verified from payment_orders where id = (select id from tests.o where k='a')), 'bank verified');
-- order b (₹69, open) must not get a credit with no UTR while an unconfirmed instant ₹69 order exists
select tests.as_user('00000000-0000-0000-0000-0000000008a1');
select tests.new_order('e', '00000000-0000-0000-0000-0000000008f2');
select is(report_result((select id from tests.o where k='e'),
  'ApprovalRefNo=533344445555&Status=SUCCESS&txnRef=' || (select ref from tests.o where k='e')) ->> 'status', 'paid', 'second instant buy');
reset role;
select tests.as_user('00000000-0000-0000-0000-0000000008a2');
select tests.new_order('f', '00000000-0000-0000-0000-0000000008f2');
reset role;
select is(bank_credit_received(null, 25900, 'Rs 259 credited') ->> 'result', 'ambiguous', 'no-UTR ₹259 credit is not given to another buyer');
select is(tests.st('f'), 'pending', 'other buyer still pending');

-- ===== at most 3 instant activations per buyer per day =====
select tests.as_user('00000000-0000-0000-0000-0000000008a1');
select tests.new_order('g', '00000000-0000-0000-0000-0000000008f1');
select is(report_result((select id from tests.o where k='g'),
  'ApprovalRefNo=544455556666&Status=SUCCESS&txnRef=' || (select ref from tests.o where k='g')) ->> 'status', 'paid', 'third is instant');
select tests.new_order('h', '00000000-0000-0000-0000-0000000008f1');
select is(report_result((select id from tests.o where k='h'),
  'ApprovalRefNo=555566667777&Status=SUCCESS&txnRef=' || (select ref from tests.o where k='h')) ->> 'status', 'review', 'fourth -> owner verifies');
reset role;

-- ===== owner switch =====
select tests.as_user('00000000-0000-0000-0000-0000000008a2');
select throws_ok($$ select admin_set_activation_mode('manual') $$, null, null, 'buyers cannot change the mode');
reset role;
select tests.as_user('00000000-0000-0000-0000-0000000008a3');
select lives_ok($$ select admin_set_activation_mode('manual') $$, 'owner switches to manual');
reset role;
select tests.as_user('00000000-0000-0000-0000-0000000008a2');
select is(report_result((select id from tests.o where k='f'),
  'ApprovalRefNo=566677778888&Status=SUCCESS&txnRef=' || (select ref from tests.o where k='f')) ->> 'status', 'review', 'manual mode -> owner verifies');
reset role;

select * from finish();
rollback;
