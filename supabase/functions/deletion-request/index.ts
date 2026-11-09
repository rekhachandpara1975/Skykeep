// Public web form: request account deletion (or partial data deletion) by email.
import { admin, json, serve } from '../_shared/util.ts';

const EMAIL = /^[^@\s]{1,64}@[^@\s]{1,190}\.[a-z]{2,}$/i;

serve(async (req) => {
  const { email, scope, details } = await req.json();
  if (typeof email !== 'string' || !EMAIL.test(email)) return json({ error: 'valid email required' }, 400);
  const what = scope === 'some' ? 'Delete only some data' : 'Delete account and all data';
  const { error } = await admin().from('support_requests').insert({
    kind: 'deletion',
    email: email.slice(0, 200),
    details: `${what}\n${String(details ?? '').slice(0, 3000)}`,
  });
  if (error) throw error;
  return json({ ok: true });
});
