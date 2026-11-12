// Owner-only: apply a provider/bank confirmation by hand (same checks as the webhook).
import { admin, caller, isOwner, json, serve } from '../_shared/util.ts';

serve(async (req) => {
  const c = await caller(req);
  if (!c || !(await isOwner(c.user.id))) return json({ error: 'owner only' }, 403);
  const { reference, utr, amount_paise } = await req.json();
  const { data, error } = await admin().rpc('provider_payment_update', {
    p_reference: String(reference),
    p_utr: String(utr),
    p_amount_paise: Number(amount_paise),
  });
  if (error) throw error;
  return json({ result: data });
});
