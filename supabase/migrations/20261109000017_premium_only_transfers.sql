-- Downloads and uploading channel content are for Premium members only (paid plan; in free mode, full-access members).
-- Ads / organic visibility is untouched: organic users, even with a plan, still need admin approval to see ads content.

create or replace function public.can_view(p_item_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'visible', i.id is not null and public.post_visible(i.post_id),
    'full', i.id is not null and public.post_visible(i.post_id) and (not i.is_premium or public.has_full_access()),
    'download', i.id is not null and public.post_visible(i.post_id) and public.has_full_access(),
    'trailer', i.id is not null and public.post_visible(i.post_id) and i.is_premium
               and not public.has_full_access() and i.trailer_key is not null)
  from (select 1) x left join public.post_items i on i.id = p_item_id
$$;

create or replace function public.can_upload_channel(cid uuid, uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.can_manage_channel(cid, uid) or exists (select 1 from public.channels c
    where c.id = cid and c.created_by = uid and c.review_status = 'approved'
      and c.status in ('published','active') and not c.hidden
      and public.is_member(uid) and public.has_consent(uid) and public.has_full_access(uid))
$$;
