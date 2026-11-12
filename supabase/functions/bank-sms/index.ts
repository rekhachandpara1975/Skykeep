// Receives the owner's bank credit SMS from an SMS-forwarder app on the phone that has the bank SIM.
// Auth: secret BANK_SMS_KEY, sent as header "X-SkyKeep-Key" or "?key=" in the URL (forwarder apps support either).
// Accepts JSON ({ "text"|"message"|"msg"|"body"|"sms": "...", "from"|"sender": "..." }), form data, or plain text.
// Only the server matches and activates (bank_credit_received). Non-credit SMS are ignored.
import { admin, json, safeEqual, serve } from '../_shared/util.ts';
import { parseBankSms } from '../_shared/bank_sms.ts';

serve(async (req) => {
  const secret = Deno.env.get('BANK_SMS_KEY');
  if (!secret) return json({ error: 'bank SMS disabled: set BANK_SMS_KEY' }, 503);
  const url = new URL(req.url);
  const key = req.headers.get('X-SkyKeep-Key') ?? url.searchParams.get('key') ?? '';
  if (!safeEqual(key, secret)) return json({ error: 'forbidden' }, 403);

  const raw = await req.text();
  let text = raw, from = '';
  try {
    const j = JSON.parse(raw);
    text = String(j.text ?? j.message ?? j.msg ?? j.body ?? j.sms ?? j.content ?? '');
    from = String(j.from ?? j.sender ?? j.address ?? '');
  } catch {
    const f = new URLSearchParams(raw);
    if (f.has('text') || f.has('message') || f.has('msg')) {
      text = f.get('text') ?? f.get('message') ?? f.get('msg') ?? '';
      from = f.get('from') ?? f.get('sender') ?? '';
    }
  }
  const allowed = (Deno.env.get('BANK_SMS_SENDERS') ?? '').split(',').map((s) => s.trim().toUpperCase()).filter(Boolean);
  if (allowed.length && from && !allowed.some((s) => from.toUpperCase().includes(s))) return json({ ignored: 'sender not allowed' });

  const credit = parseBankSms(text);
  if (!credit) return json({ ignored: 'not a credit SMS' });
  const { data, error } = await admin().rpc('bank_credit_received', {
    p_utr: credit.utr, p_amount_paise: credit.amountPaise, p_raw: `${from} ${text}`.trim().slice(0, 1000), p_payer: credit.payer,
  });
  if (error) throw error;
  return json(data);
});
