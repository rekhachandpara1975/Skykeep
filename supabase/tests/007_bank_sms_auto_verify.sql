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
create function tests.st(k text) returns text language sql as $$ select status from public.payment_orders where id = (select id from tests.o where tests.o.k = st.k) $$;

insert into auth.users (id, email, is_anonymous) values
  ('00000000-0000-0000-0000-0000000007a1', 'b1@x.test', false),
  ('00000000-0000-0000-0000-0000000007a2', 'b2@x.test', false),
  ('00000000-0000-0000-0000-0000000007a3', 'b3@x.test', false);
insert into private.user_sources values ('00000000-0000-0000-0000-0000000007a1', 'ads'),
  ('00000000-0000-0000-0000-0000000007a2', 'ads'), ('00000000-0000-0000-0000-0000000007a3', 'ads');
update plans set active = false;
insert into plans (id, code, name, price_inr, duration_days) values
  ('00000000-0000-0000-0000-0000000007f1', 'b_trial', 'Trial', 69, 2),
  ('00000000-0000-0000-0000-0000000007f2', 'b_gold', 'Gold', 259, 30);
update payment_settings set upi_id = '2728412a@bandhan', payee_name = 'As Enterprice';

-- ===== 1. UTR known from the UPI app, then the bank SMS arrives → paid automatically =====
select tests.as_user('00000000-0000-0000-0000-0000000007a1');
insert into tests.o select 'a', (j->>'order_id')::uuid, j->>'reference' from (select create_order('00000000-0000-0000-0000-0000000007f1') j) x;
select is(report_result((select id from tests.o where k='a'),
  'txnId=AXI0001&ApprovalRefNo=411122223333&Status=SUCCESS&txnRef=' || (select ref from tests.o where k='a')) ->> 'status', 'review',
  'phone SUCCESS alone -> verifying');
select is((my_status() ->> 'is_premium')::boolean, false, 'not premium from the phone answer');
reset role;
select tests.as_service();
select is(bank_credit_received('411122223333', 6900, 'Rs 69.00 credited ... UPI Ref 411122223333') ->> 'result', 'paid', 'bank SMS with same UTR + amount -> paid');
select is(tests.st('a'), 'paid', 'order paid');
select is((select source from subscriptions where order_id = (select id from tests.o where k='a')), 'provider_api', 'plan granted from bank confirmation');
select is((select bank_verified from payment_orders where id = (select id from tests.o where k='a')), true, 'marked bank verified');
select is(bank_credit_received('411122223333', 6900) ->> 'result', 'duplicate', 'same SMS twice does nothing');
select is((select count(*)::int from subscriptions where order_id = (select id from tests.o where k='a')), 1, 'still one subscription');
reset role;
select tests.as_user('00000000-0000-0000-0000-0000000007a1');
select is((my_status() ->> 'is_premium')::boolean, true, 'buyer is premium');
reset role;

-- ===== 2. Bank SMS first, buyer types the UTR later → paid at that moment =====
select tests.as_user('00000000-0000-0000-0000-0000000007a2');
insert into tests.o select 'b', (j->>'order_id')::uuid, j->>'reference' from (select create_order('00000000-0000-0000-0000-0000000007f2') j) x;
reset role;
select tests.as_user('00000000-0000-0000-0000-0000000007a3');
insert into tests.o select 'b2', (j->>'order_id')::uuid, j->>'reference' from (select create_order('00000000-0000-0000-0000-0000000007f2') j) x;
reset role;
select tests.as_service();
select is(bank_credit_received('522233334444', 25900) ->> 'result', 'ambiguous', 'two open ₹259 orders -> not guessed');
reset role;
select tests.as_user('00000000-0000-0000-0000-0000000007a2');
select is(report_result((select id from tests.o where k='b'), '') ->> 'status', 'pending', 'buyer came back without data');
select is(submit_payment_proof((select ref from tests.o where k='b'), '5222 3333 4444') ->> 'status', 'review', 'buyer types the UTR');
reset role;
select is(tests.st('b'), 'paid', 'stored bank credit matched the typed UTR -> paid');
select is(tests.st('b2'), 'pending', 'the other ₹259 order untouched');

-- ===== 3. Amount-only match when exactly one open order has that amount =====
select tests.as_service();
select is(bank_credit_received('633344445555', 25900) ->> 'result', 'paid', 'only one open ₹259 order left -> paid by amount');
select is(tests.st('b2'), 'paid', 'second order paid');
reset role;

-- ===== 4. Wrong amount → review, never auto =====
select tests.as_user('00000000-0000-0000-0000-0000000007a3');
insert into tests.o select 'c', (j->>'order_id')::uuid, j->>'reference' from (select create_order('00000000-0000-0000-0000-0000000007f1') j) x;
select submit_payment_proof((select ref from tests.o where k='c'), '744455556666');
reset role;
select tests.as_service();
select is(bank_credit_received('744455556666', 5000) ->> 'result', 'amount_mismatch', 'paid ₹50 for a ₹69 order');
select is(tests.st('c'), 'review', 'stays in review for the owner');
select matches((select admin_note from payment_orders where id = (select id from tests.o where k='c')), 'check before approving', 'note explains why');

-- ===== 5. A credit with no order waits; a used UTR is never reused =====
select is(bank_credit_received('855566667777', 12900) ->> 'result', 'unmatched', 'credit with no order -> kept for later');
select is(bank_credit_received(null, 1) ->> 'result', 'unmatched', 'credit without UTR and no order -> kept');
reset role;
select tests.as_user('00000000-0000-0000-0000-0000000007a1');
select throws_ok($$ select bank_credit_received('999988887777', 6900) $$, '42501', null, 'apps cannot report bank credits');
select throws_ok($$ select admin_bank_credits() $$, '42501', null, 'buyers cannot read bank credits');
reset role;

select * from finish();
rollback;
