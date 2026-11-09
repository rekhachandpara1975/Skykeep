// User deletes their own account in-app. Payment rows are kept (user_id set null) for tax records.
import { admin, caller, json, removeUserFiles, serve } from '../_shared/util.ts';

serve(async (req) => {
  const c = await caller(req);
  if (!c) return json({ error: 'unauthorized' }, 401);
  await removeUserFiles(c.user.id);
  const { error } = await admin().auth.admin.deleteUser(c.user.id);
  if (error) throw error;
  return json({ ok: true });
});
