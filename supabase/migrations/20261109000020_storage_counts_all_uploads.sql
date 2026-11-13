-- Storage card should reflect everything the user has uploaded: their personal cloud files AND the
-- content they uploaded to channels they own. used_bytes is now computed live (also self-heals any
-- drift in the stored counter). Quota enforcement on cloud_files is unchanged.
create or replace function public.my_status() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid(); pr public.profiles; sub record; m public.app_mode; ps public.play_settings;
  v_used bigint;
begin
  select * into pr from public.profiles where id = v_uid;
  select * into m from public.app_mode limit 1;
  select * into ps from public.play_settings limit 1;
  select s.ends_at, p.name into sub from public.subscriptions s left join public.plans p on p.id = s.plan_id
   where s.user_id = v_uid and s.status = 'active' and s.ends_at > now() order by s.ends_at desc limit 1;
  v_used := coalesce((select sum(size_bytes) from public.cloud_files where user_id = v_uid), 0)
          + coalesce((select sum(pi.size_bytes) from public.post_items pi
                      join public.posts po on po.id = pi.post_id
                      join public.channels c on c.id = po.channel_id
                      where c.created_by = v_uid), 0);
  return jsonb_build_object(
    'user_id', v_uid,
    'is_guest', not public.is_member(v_uid),
    'is_admin', public.is_admin(v_uid),
    'source', public.source_of(v_uid),
    'has_ads_access', public.has_ads_access(v_uid),
    'is_premium', public.has_full_access(v_uid),
    'has_plan', sub.ends_at is not null,
    'plan_name', sub.name,
    'plan_ends_at', sub.ends_at,
    'used_bytes', v_used,
    'quota_bytes', public.quota_bytes(v_uid),
    'free_mode', m.free_mode,
    'paid_enabled', not m.free_mode,
    'access_status', coalesce(pr.ads_access_status, 'none'),
    'payments_available', public.payments_available(),
    'free_plans_for', m.free_plans_for,
    'plans_visible', public.plans_visible_for_me(v_uid),
    'play_verified', coalesce(pr.play_verified, false),
    'play_billing_enabled', ps.play_billing_enabled and ps.google_approval_confirmed,
    'display_name', pr.display_name,
    'avatar_url', pr.avatar_url);
end $$;
