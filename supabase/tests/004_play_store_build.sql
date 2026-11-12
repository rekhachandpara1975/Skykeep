begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select no_plan();

insert into auth.users (id, email, is_anonymous) values ('00000000-0000-0000-0000-0000000004a1', 'owner4@x.test', false);
insert into admins (user_id, role) values ('00000000-0000-0000-0000-0000000004a1', 'owner');

select hasnt_table('public', 'play_products', 'no Play products table');
select hasnt_table('public', 'play_purchases', 'no Play purchases table');
select is((select play_billing_enabled from play_settings), false, 'Play billing off');
select throws_ok($$ update play_settings set google_approval_confirmed = true, play_billing_enabled = true $$, '23514', null,
  'Play billing can never be turned on');
select is((my_status() ->> 'play_billing_enabled')::boolean, false, 'apps are told billing is off');
select hasnt_function('public', 'play_record_purchase', 'no Play purchase recording');
select has_function('public', 'enable_play_free_cloud', 'Play Integrity free tier still exists');

select * from finish();
rollback;
