// Owner deletes a user's account (e.g. from a deletion request) and closes the request.
import { admin, caller, isOwner, json, removeUserFiles, serve } from '../_shared/util.ts';

serve(async (req) => {
  const c = await caller(req);
  if (!c || !(await isOwner(c.user.id))) return json({ error: 'owner only' }, 403);
  const { user_id, request_id } = await req.json();
  if (typeof user_id !== 'string') return json({ error: 'user_id required' }, 400);
  if (user_id === c.user.id) return json({ error: 'cannot delete yourself here' }, 400);
  const sb = admin();
  const { data: a } = await sb.from('admins').select('role').eq('user_id', user_id).maybeSingle();
  if (a) return json({ error: 'remove admin role first' }, 400);
  await removeUserFiles(user_id);
  const { error } = await sb.auth.admin.deleteUser(user_id);
  if (error) throw error;
  if (request_id) await sb.from('support_requests').update({ status: 'closed' }).eq('id', request_id);
  return json({ ok: true });
});
