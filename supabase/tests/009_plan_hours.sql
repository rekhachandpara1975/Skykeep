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

insert into auth.users (id, email, is_anonymous) values ('00000000-0000-0000-0000-0000000009a1', 'h1@x.test', false);
insert into private.user_sources values ('00000000-0000-0000-0000-0000000009a1', 'ads');
update plans set active = false where true;
update payment_settings set upi_id = '2728412a@bandhan', payee_name = 'As Enterprice', activation_mode = 'instant' where true;

insert into plans (id, code, name, price_inr, duration_days, duration_hours) values
  ('00000000-0000-0000-0000-0000000009f1', 'h_6h', '6 Hours', 19, 1, 6),
  ('00000000-0000-0000-0000-0000000009f2', 'h_30h', '30 Hours', 39, 1, 30);
select is((select duration_days from plans where code = 'h_6h'), 1, '6 hours → shown as 1 day for old screens');
select is((select duration_days from plans where code = 'h_30h'), 2, '30 hours rounds up to 2 days');
select throws_ok($$ update plans set duration_hours = 0 where code = 'h_6h' $$, '23514', null, 'hours must be at least 1');

select tests.as_user('00000000-0000-0000-0000-0000000009a1');
insert into tests.o select 'a', (j->>'order_id')::uuid, j->>'reference' from (select create_order('00000000-0000-0000-0000-0000000009f1') j) x;
select is(report_result((select id from tests.o where k='a'),
  'ApprovalRefNo=611122223333&Status=SUCCESS&txnRef=' || (select ref from tests.o where k='a')) ->> 'status', 'paid', 'hour plan bought');
reset role;
select is((select duration_hours from payment_orders where id = (select id from tests.o where k='a')), 6, 'order keeps the hours');
select ok((select ends_at between now() + interval '5 hours 59 minutes' and now() + interval '6 hours 1 minute'
           from subscriptions where order_id = (select id from tests.o where k='a')), 'plan lasts exactly 6 hours');

-- changing a plan from hours back to days
update plans set duration_hours = null, duration_days = 3 where code = 'h_30h';
select is((select duration_days from plans where code = 'h_30h'), 3, 'back to days');
select is(private.plan_length(3, null), interval '3 days', 'day plans unchanged');

select * from finish();
rollback;
