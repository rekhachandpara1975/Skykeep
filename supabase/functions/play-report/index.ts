// User Choice Billing: reports UPI (alternative billing) transactions to Google within 24 h
// (externaltransactions.createexternaltransaction). Run hourly by cron with the service role key.
// Exits while play_settings.play_billing_enabled AND google_approval_confirmed are not both true.
// Secrets: GOOGLE_SERVICE_ACCOUNT_JSON, PLAY_PACKAGE, PLAY_GST_RATE (default 0.18 — prices include GST)
import { GoogleAuth } from 'npm:google-auth-library@9.14.1';
import { admin, json, serve } from '../_shared/util.ts';

serve(async (req) => {
  if (req.headers.get('Authorization') !== `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`) {
    return json({ error: 'forbidden' }, 403);
  }
  const sb = admin();
  const { data: s } = await sb.from('play_settings').select('*').single();
  if (!s?.play_billing_enabled || !s?.google_approval_confirmed) return json({ skipped: 'play billing is off' });
  const sa = Deno.env.get('GOOGLE_SERVICE_ACCOUNT_JSON');
  const pkg = Deno.env.get('PLAY_PACKAGE') ?? 'com.skykeep.play';
  const gst = Number(Deno.env.get('PLAY_GST_RATE') ?? '0.18');
  if (!sa) return json({ error: 'not configured' }, 503);
  const client = await new GoogleAuth({
    credentials: JSON.parse(sa), scopes: ['https://www.googleapis.com/auth/androidpublisher'],
  }).getClient();

  const { data: rows, error } = await sb.rpc('play_pending_reports', { p_limit: 50 });
  if (error) throw error;
  let reported = 0, failed = 0;
  for (const r of rows ?? []) {
    const totalMicros = BigInt(r.amount_paise) * 10_000n;                    // paise → micros
    const preTax = BigInt(Math.round(Number(totalMicros) / (1 + gst)));
    try {
      await client.request({
        url: `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${pkg}/externalTransactions?externalTransactionId=${r.id}`,
        method: 'POST',
        data: {
          originalPreTaxAmount: { priceMicros: preTax.toString(), currency: 'INR' },
          originalTaxAmount: { priceMicros: (totalMicros - preTax).toString(), currency: 'INR' },
          transactionTime: new Date(r.paid_at).toISOString(),
          oneTimeTransaction: { externalTransactionToken: r.external_transaction_token },
          userTaxAddress: { regionCode: 'IN', administrativeArea: r.buyer_state },
        },
      });
      await sb.rpc('play_mark_report', { p_id: r.id, p_ok: true });
      reported++;
    } catch (e) {
      // 409 = already reported with this id → treat as done
      // deno-lint-ignore no-explicit-any
      const status = (e as any)?.response?.status;
      await sb.rpc('play_mark_report', { p_id: r.id, p_ok: status === 409, p_error: status === 409 ? null : String(e) });
      status === 409 ? reported++ : failed++;
    }
  }
  return json({ reported, failed });
});
