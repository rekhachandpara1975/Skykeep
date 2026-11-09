// User Choice Billing: reports alternative-billing transactions to Google. Prepared but OFF:
// exits unless play_settings.play_billing_enabled AND google_approval_confirmed are both true.
// Run by cron with the service role key. Secrets: GOOGLE_SERVICE_ACCOUNT_JSON, PLAY_PACKAGE.
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
  if (!sa) return json({ error: 'not configured' }, 503);
  const client = await new GoogleAuth({
    credentials: JSON.parse(sa),
    scopes: ['https://www.googleapis.com/auth/androidpublisher'],
  }).getClient();
  const { data: rows } = await sb.from('play_purchases').select('*').eq('kind', 'alternative').is('reported_at', null).limit(50);
  let reported = 0;
  for (const r of rows ?? []) {
    await client.request({
      url: `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${pkg}/externalTransactions?externalTransactionId=${r.id}`,
      method: 'POST',
      data: { externalTransactionToken: r.external_transaction_token, transactionTime: r.created_at },
    });
    await sb.from('play_purchases').update({ reported_at: new Date().toISOString() }).eq('id', r.id);
    reported++;
  }
  return json({ reported });
});
