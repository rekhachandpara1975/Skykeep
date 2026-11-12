// Signed upload/download/delete for personal cloud. Quota is enforced by RLS on cloud_files.
import { caller, json, serve } from '../_shared/util.ts';

serve(async (req) => {
  const c = await caller(req);
  if (!c) return json({ error: 'unauthorized' }, 401);
  const body = await req.json();
  const { db, user } = c;

  if (body.action === 'upload') {
    const name = String(body.name ?? '').slice(0, 255);
    const size = Number(body.size);
    if (!name || !Number.isFinite(size) || size < 0) return json({ error: 'name and size required' }, 400);
    const key = `${user.id}/${crypto.randomUUID()}-${name.replace(/[^\w.-]+/g, '_')}`;
    const { data: row, error } = await db
      .from('cloud_files')
      .insert({ name, size_bytes: size, mime: body.mime ?? null, folder_id: body.folder_id ?? null, storage_key: key })
      .select()
      .single();
    if (error) return json({ error: error.code === '42501' ? 'storage_full' : error.message }, 403);
    const { data: up, error: e2 } = await db.storage.from('cloud').createSignedUploadUrl(key);
    if (e2) {
      await db.from('cloud_files').delete().eq('id', row.id);
      throw e2;
    }
    return json({ file: row, upload_url: up.signedUrl, token: up.token, path: key });
  }

  if (body.action === 'download') {
    const { data: f } = await db.from('cloud_files').select('storage_key,name').eq('id', body.id).maybeSingle();
    if (!f) return json({ error: 'not found' }, 404);
    const { data, error } = await db.storage.from('cloud').createSignedUrl(f.storage_key, 3600);
    if (error) throw error;
    return json({ url: data.signedUrl, name: f.name, expires_in: 3600 });
  }

  if (body.action === 'delete') {
    const { data: f } = await db.from('cloud_files').select('id,storage_key').eq('id', body.id).maybeSingle();
    if (!f) return json({ error: 'not found' }, 404);
    await db.storage.from('cloud').remove([f.storage_key]);
    const { error } = await db.from('cloud_files').delete().eq('id', f.id);
    if (error) throw error;
    return json({ ok: true });
  }

  return json({ error: 'unknown action' }, 400);
});
