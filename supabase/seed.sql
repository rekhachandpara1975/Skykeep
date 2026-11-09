-- Local/CI demo data only (never run against production; `supabase db push` does not apply seed.sql).
insert into public.plans (code, name, price_inr, duration_days, perks, badge, position, free_eligible) values
  ('monthly', 'Monthly', 99, 30, '{"2 TB cloud storage","Full videos","Downloads"}', null, 1, true),
  ('quarterly', 'Quarterly', 249, 90, '{"2 TB cloud storage","Full videos","Downloads"}', 'Popular', 2, false),
  ('yearly', 'Yearly', 799, 365, '{"2 TB cloud storage","Full videos","Downloads","Best price"}', 'Best value', 3, false)
on conflict (code) do nothing;

insert into public.channels (name, description, category, tags, audience, review_status, status) values
  ('SkyKeep Tips', 'How to get the most from your cloud.', 'Tech', '{tips,cloud}', 'all', 'approved', 'published'),
  ('Travel Diaries', 'Short travel films.', 'Travel', '{travel}', 'all', 'approved', 'published');
