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

insert into auth.users (id, email, is_anonymous) values
  ('00000000-0000-0000-0000-0000000005a1', 'owner5@x.test', false),
  ('00000000-0000-0000-0000-0000000005a2', 'buyer5@x.test', false),
  ('00000000-0000-0000-0000-0000000005a3', 'other5@x.test', false);
insert into admins (user_id, role) values ('00000000-0000-0000-0000-0000000005a1', 'owner');
insert into private.user_sources values ('00000000-0000-0000-0000-0000000005a2', 'ads'), ('00000000-0000-0000-0000-0000000005a3', 'ads');
update plans set active = false;
insert into plans (id, code, name, price_inr, duration_days) values
  ('00000000-0000-0000-0000-0000000005f1', 'u_month', 'Monthly', 99, 30),
  ('00000000-0000-0000-0000-0000000005f2', 'u_year', 'Yearly', 799, 365);
update payment_settings set upi_id = '2728412a@bandhan', payee_name = 'As Enterprice';

-- ===== plan page + order =====
select tests.as_user('00000000-0000-0000-0000-0000000005a2');
select is(plan_offers() ->> 'payee_name', 'As Enterprice', 'plans page can say who gets paid');
insert into tests.o select 'a', (j->>'order_id')::uuid, j->>'reference' from (select create_order('00000000-0000-0000-0000-0000000005f1') j) x;
select is((select status from payment_orders where id = (select id from tests.o where k='a')), 'pending', 'new order waits for payment');
select ok((select expires_at from payment_orders where id = (select id from tests.o where k='a')) between now() + interval '29 minutes' and now() + interval '31 minutes', 'order expires in 30 minutes');
select is((select count(*)::int from payment_order_events where order_id = (select id from tests.o where k='a')), 1, 'creation logged');
select is(create_order('00000000-0000-0000-0000-0000000005f1') ->> 'order_id', (select id::text from tests.o where k='a'), 'one open order per plan');
reset role;
select is((select count(*)::int from meta_events where event_name = 'InitiateCheckout' and order_id = (select id from tests.o where k='a')), 1, 'InitiateCheckout queued');
select tests.as_user('00000000-0000-0000-0000-0000000005a2');

-- ===== phone answers are only hints =====
select is(report_result((select id from tests.o where k='a'), '') ->> 'status', 'pending', 'no data (cancelled) keeps waiting');
select is((report_result((select id from tests.o where k='a'), '') ->> 'needs_utr')::boolean, true, 'app offers "I have paid"');
select is(report_result((select id from tests.o where k='a'), 'Status=SUBMITTED&txnRef=' || (select ref from tests.o where k='a')) ->> 'status', 'pending', 'SUBMITTED -> still pending');
select is(report_result((select id from tests.o where k='a'),
  'txnId=123456789012&Status=SUCCESS&txnRef=' || (select ref from tests.o where k='a')) ->> 'status', 'review', 'SUCCESS -> verification');
select is((select utr from payment_orders where id = (select id from tests.o where k='a')), '123456789012', '12-digit txn id kept as UTR');
select is((my_status() ->> 'is_premium')::boolean, false, 'not premium until approved');

-- ===== buyer proof =====
insert into tests.o select 'b', (j->>'order_id')::uuid, j->>'reference' from (select create_order('00000000-0000-0000-0000-0000000005f2') j) x;
select is(submit_payment_proof((select ref from tests.o where k='b'), '12345') ->> 'error', 'UTR must be 12 digits', 'bad UTR format');
select is(submit_payment_proof((select ref from tests.o where k='b'), '123456789012') ->> 'error', 'this UTR was already used for another payment', 'duplicate UTR rejected');
select throws_ok($$ select submit_payment_proof((select ref from tests.o where k='b'), '222233334444', 'someone-else/x.png') $$, 'invalid screenshot');
select is(submit_payment_proof((select ref from tests.o where k='b'), '2222 3333 4444',
  '00000000-0000-0000-0000-0000000005a2/' || (select ref from tests.o where k='b') || '/shot.png') ->> 'status', 'review', 'UTR + screenshot -> verification');
select is((select utr || '/' || utr_source from payment_orders where id = (select id from tests.o where k='b')), '222233334444/buyer', 'UTR stored, spaces removed');
reset role;
select tests.as_user('00000000-0000-0000-0000-0000000005a3');
select throws_ok($$ select submit_payment_proof((select ref from tests.o where k='b'), '999988887777') $$, 'order not found');
reset role;

-- ===== owner verifies =====
select tests.as_user('00000000-0000-0000-0000-0000000005a2');
select throws_ok($$ select admin_approve_review((select id from tests.o where k='b')) $$, '42501', null, 'buyers cannot approve');
reset role;
select tests.as_user('00000000-0000-0000-0000-0000000005a1');
select admin_approve_review((select id from tests.o where k='b'));
select is((select status from payment_orders where id = (select id from tests.o where k='b')), 'paid', 'approve marks paid');
select is((select source from subscriptions where order_id = (select id from tests.o where k='b')), 'admin', 'plan granted by owner approval');
select lives_ok($$ select admin_approve_review((select id from tests.o where k='b')) $$, 'approve is idempotent');
select is((select count(*)::int from subscriptions where order_id = (select id from tests.o where k='b')), 1, 'still one subscription');
select is((select changed_by from payment_order_events where order_id = (select id from tests.o where k='b') and new_status = 'paid'),
  '00000000-0000-0000-0000-0000000005a1'::uuid, 'who approved is logged');
select admin_reject_order((select id from tests.o where k='a'), 'not in bank statement');
select is((select status from payment_orders where id = (select id from tests.o where k='a')), 'rejected', 'reject');
select is((select note from payment_order_events where order_id = (select id from tests.o where k='a') and new_status = 'rejected'), 'not in bank statement', 'reason logged');
reset role;
select tests.as_user('00000000-0000-0000-0000-0000000005a2');
select is((my_status() ->> 'is_premium')::boolean, true, 'premium only after approval');
reset role;

-- ===== expiry =====
select tests.as_user('00000000-0000-0000-0000-0000000005a3');
insert into tests.o select 'c', (j->>'order_id')::uuid, j->>'reference' from (select create_order('00000000-0000-0000-0000-0000000005f1') j) x;
reset role;
update payment_orders set expires_at = now() - interval '1 minute' where id = (select id from tests.o where k='c');
select tests.as_user('00000000-0000-0000-0000-0000000005a3');
select is(order_status((select id from tests.o where k='c')) ->> 'status', 'expired', 'unpaid order expires after 30 minutes');
select isnt(create_order('00000000-0000-0000-0000-0000000005f1') ->> 'order_id', (select id::text from tests.o where k='c'), 'start again -> new order');
select is(submit_payment_proof((select ref from tests.o where k='c'), '555566667777') ->> 'status', 'review', 'late proof for an expired order still goes to verification');
reset role;
select tests.as_user('00000000-0000-0000-0000-0000000005a1');
select throws_ok($$ select admin_approve_review((select id from tests.o where k='a')) $$, 'order is rejected');
reset role;

-- approve needs a UTR
select tests.as_user('00000000-0000-0000-0000-0000000005a3');
insert into tests.o select 'd', (j->>'order_id')::uuid, j->>'reference' from (select create_order('00000000-0000-0000-0000-0000000005f2') j) x;
reset role;
select tests.as_user('00000000-0000-0000-0000-0000000005a1');
select throws_ok($$ select admin_approve_review((select id from tests.o where k='d')) $$, 'no UTR — use Mark paid with the 12-digit UTR from your bank');
reset role;

-- ===== rate limits =====
select tests.as_user('00000000-0000-0000-0000-0000000005a3');
select throws_ok($$ do $b$ begin for i in 1..12 loop
  perform create_order(case when i % 2 = 0 then '00000000-0000-0000-0000-0000000005f1'::uuid else '00000000-0000-0000-0000-0000000005f2'::uuid end);
end loop; end $b$ $$, 'too many payment attempts — try again in an hour');
select throws_ok($$ do $b$ begin for i in 1..12 loop
  perform submit_payment_proof((select ref from tests.o where k='d'), 'bad');
end loop; end $b$ $$, 'too many attempts — try again in an hour');
reset role;

select * from finish();
rollback;
