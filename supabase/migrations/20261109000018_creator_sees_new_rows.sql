-- INSERT ... RETURNING (what the app does when creating a channel or post) re-checks the SELECT policy on the new row.
-- channel_visible()/post_visible() are STABLE functions that look the row up again by id, and they cannot see a row
-- created in the same statement, so non-admin creators got "new row violates row-level security policy".
-- Add a direct column check that works on the new row itself.
drop policy if exists channels_read on public.channels;
create policy channels_read on public.channels for select
  using (created_by = auth.uid() or public.channel_visible(id));

drop policy if exists posts_read on public.posts;
create policy posts_read on public.posts for select
  using (public.can_upload_channel(channel_id) or public.post_visible(id));
