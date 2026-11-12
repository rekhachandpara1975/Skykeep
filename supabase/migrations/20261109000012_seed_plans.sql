-- The owner's launch plans (12 Nov 2026). Data only: edit prices, perks or badges later in Admin › Plans.
-- Inserted once; re-running never overwrites changes made in the admin panel.
insert into public.plans (code, name, price_inr, duration_days, perks, badge, position, active) values
  ('trial',    'Trial',         69,   2, array['2 TB cloud storage', 'Full premium videos', 'Downloads'], null,          1, true),
  ('silver',   'Silver Plan',  129,   7, array['2 TB cloud storage', 'Full premium videos', 'Downloads'], null,          2, true),
  ('gold',     'Gold Plan',    259,  30, array['2 TB cloud storage', 'Full premium videos', 'Downloads'], 'Popular',     3, true),
  ('platinum', 'Platinum Plan', 599, 180, array['2 TB cloud storage', 'Full premium videos', 'Downloads'], null,         4, true),
  ('diamond',  'Diamond Plan', 899, 365, array['2 TB cloud storage', 'Full premium videos', 'Downloads'], 'Best value',  5, true)
on conflict (code) do nothing;
