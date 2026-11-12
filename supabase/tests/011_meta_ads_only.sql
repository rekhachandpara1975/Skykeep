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
  ('00000000-0000-0000-0000-00000000b1a1', 'ads@x.test', false),
  ('00000000-0000-0000-0000-00000000b1a2', 'play@x.test', false);
insert into private.user_sources values ('00000000-0000-0000-0000-00000000b1a1', 'ads'), ('00000000-0000-0000-0000-00000000b1a2', 'organic')
  on conflict (user_id) do update set source = excluded.source;
update plans set active = false where true;
insert into plans (id, code, name, price_inr, duration_days) values ('00000000-0000-0000-0000-00000000b1f1', 'm_trial', 'Trial', 69, 2);
update payment_settings set upi_id = '2728412a@bandhan', payee_name = 'As Enterprice', activation_mode = 'instant' where true;
update app_mode set free_mode = false, plans_visible_for = 'everyone' where true;

-- ads user: checkout + purchase reported
select tests.as_user('00000000-0000-0000-0000-00000000b1a1');
insert into tests.o select 'a', (j->>'order_id')::uuid, j->>'reference' from (select create_order('00000000-0000-0000-0000-00000000b1f1') j) x;
select is(report_result((select id from tests.o where k='a'), 'ApprovalRefNo=811122223333&Status=SUCCESS&txnRef=' || (select ref from tests.o where k='a')) ->> 'status', 'paid', 'ads user paid');
reset role;
select is((select count(*)::int from meta_events where user_id = '00000000-0000-0000-0000-00000000b1a1' and event_name in ('InitiateCheckout','Purchase')), 2, 'ads user: checkout + purchase queued for Meta');

-- organic / Play user: nothing reported
select tests.as_user('00000000-0000-0000-0000-00000000b1a2');
insert into tests.o select 'b', (j->>'order_id')::uuid, j->>'reference' from (select create_order('00000000-0000-0000-0000-00000000b1f1') j) x;
select is(report_result((select id from tests.o where k='b'), 'ApprovalRefNo=822233334444&Status=SUCCESS&txnRef=' || (select ref from tests.o where k='b')) ->> 'status', 'paid', 'organic user paid');
reset role;
select is((select count(*)::int from meta_events where user_id = '00000000-0000-0000-0000-00000000b1a2'), 0, 'organic user: nothing sent to Meta');

select * from finish();
rollback;
