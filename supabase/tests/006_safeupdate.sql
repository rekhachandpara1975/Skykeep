begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select plan(1);
-- Supabase API connections reject UPDATE/DELETE without WHERE (pg_safeupdate), even inside functions.
select is((
  select count(*)::int
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace,
       lateral regexp_split_to_table(p.prosrc, ';') st
  where n.nspname in ('public', 'private')
    and st ~* '\m(update\s+\w+\.\w+\s+set|delete\s+from\s+\w+\.\w+)\M'
    and st !~* '\mwhere\M'), 0, 'no UPDATE/DELETE without WHERE inside database functions');
select * from finish();
rollback;
