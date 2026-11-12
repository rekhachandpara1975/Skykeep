-- Payments are your own UPI intent flow only (website + ads APK). No Google Play Billing, ever.
-- The Play Store build never sells anything: free tier only (Play Integrity → 15 GB).
drop table if exists public.play_purchases;
drop table if exists public.play_products;
update public.play_settings set play_billing_enabled = false, google_approval_confirmed = false;
alter table public.play_settings add constraint play_billing_never check (not play_billing_enabled);
comment on table public.play_settings is 'Play Store build settings. Billing is permanently off: Premium is sold only by UPI in the website / ads APKs.';
