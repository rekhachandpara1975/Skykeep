// Deletes a post and its media objects. Caller must be allowed to upload to the channel.
import { admin, caller, json, serve } from '../_shared/util.ts';

serve(async (req) => {
  const c = await caller(req);
  if (!c) return json({ error: 'unauthorized' }, 401);
  const { post_id } = await req.json();
  const { data: post } = await c.db.from('posts').select('id,channel_id').eq('id', post_id).maybeSingle();
  if (!post) return json({ error: 'not found' }, 404);
  const { data: ok } = await c.db.rpc('can_upload_channel', { cid: post.channel_id });
  if (!ok) return json({ error: 'forbidden' }, 403);
  const { data: items } = await c.db.from('post_items').select('media_key,thumbnail_key,trailer_key').eq('post_id', post_id);
  const keys: string[] = [];
  for (const i of items ?? []) for (const k of [i.media_key, i.thumbnail_key, i.trailer_key]) if (k) keys.push(k);
  if (keys.length) await admin().storage.from('media').remove(keys);
  const { error } = await c.db.from('posts').delete().eq('id', post_id);
  if (error) throw error;
  return json({ ok: true, removed: keys.length });
});
