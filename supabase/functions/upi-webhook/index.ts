// Optional bank/provider notification. Body is HMAC-SHA256 signed with UPI_WEBHOOK_SECRET (hex in X-Signature).
// Expected JSON: { reference, utr, amount_paise }
import { admin, hmacHex, json, safeEqual, serve } from '../_shared/util.ts';

serve(async (req) => {
  const secret = Deno.env.get('UPI_WEBHOOK_SECRET');
  if (!secret) return json({ error: 'webhook disabled' }, 503);
  const raw = await req.text();
  const sig = (req.headers.get('X-Signature') ?? '').toLowerCase();
  if (!safeEqual(sig, await hmacHex(secret, raw))) return json({ error: 'bad signature' }, 401);
  const { reference, utr, amount_paise } = JSON.parse(raw);
  const { data, error } = await admin().rpc('provider_payment_update', {
    p_reference: String(reference),
    p_utr: String(utr),
    p_amount_paise: Number(amount_paise),
  });
  if (error) throw error;
  return json({ result: data });
});
