-- playable_key now also returns the trailer for viewers who may watch the full video, so the app can play
-- the trailer first and continue straight into the full video (Netflix / Prime style).
-- People without access still get {kind:'trailer'} (or 'locked'); the access rules are unchanged.
create or replace function public.playable_key(p_item_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select case
    when i.id is null or not public.post_visible(i.post_id) then null
    when not i.is_premium or public.has_full_access() then
      jsonb_build_object('key', i.media_key, 'kind', 'full') ||
      case when i.trailer_key is not null then jsonb_build_object('trailer_key', i.trailer_key) else '{}'::jsonb end
    when i.trailer_key is not null then jsonb_build_object('key', i.trailer_key, 'kind', 'trailer')
    else jsonb_build_object('key', null, 'kind', 'locked') end
  from (select 1) x left join public.post_items i on i.id = p_item_id
$$;
