// Play build, Google Play path: verify a subscription purchase token with Google
// (purchases.subscriptionsv2.get), acknowledge it, and record the entitlement until Google's expiry.
// Also used on app resume to recover purchases (send every token from queryPurchasesAsync).
// Refuses while play_settings.play_billing_enabled AND google_approval_confirmed are not both true.
// Secrets: GOOGLE_SERVICE_ACCOUNT_JSON (Android Publisher access), PLAY_PACKAGE (com.skykeep.play)
import { GoogleAuth } from 'npm:google-auth-library@9.14.1';
import { admin, caller, json, serve } from '../_shared/util.ts';

const hex = async (s: string) =>
  [...new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s)))]
    .map((b) => b.toString(16).padStart(2, '0')).join('');

serve(async (req) => {
  const c = await caller(req);
  if (!c) return json({ error: 'unauthorized' }, 401);
  const sb = admin();
  const { data: s } = await sb.from('play_settings').select('*').single();
  if (!s?.play_billing_enabled || !s?.google_approval_confirmed) return json({ error: 'play billing is off' }, 409);

  const body = await req.json().catch(() => ({}));
  const tokens: { productId: string; purchaseToken: string }[] = Array.isArray(body.purchases)
    ? body.purchases : [{ productId: body.productId, purchaseToken: body.purchaseToken }];
  if (!tokens.length || tokens.some((t) => typeof t?.purchaseToken !== 'string' || typeof t?.productId !== 'string')) {
    return json({ error: 'productId and purchaseToken required' }, 400);
  }
  const sa = Deno.env.get('GOOGLE_SERVICE_ACCOUNT_JSON');
  const pkg = Deno.env.get('PLAY_PACKAGE') ?? 'com.skykeep.play';
  if (!sa) return json({ error: 'play billing not configured' }, 503);
  const client = await new GoogleAuth({
    credentials: JSON.parse(sa), scopes: ['https://www.googleapis.com/auth/androidpublisher'],
  }).getClient();
  const base = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${pkg}/purchases/subscriptions`;
  const expectedAccount = await hex(c.user.id);

  const results = [];
  for (const t of tokens.slice(0, 20)) {
    // deno-lint-ignore no-explicit-any
    const { data: p } = await client.request<any>({ url: `${base}v2/tokens/${encodeURIComponent(t.purchaseToken)}` });
    const account = p.externalAccountIdentifiers?.obfuscatedExternalAccountId;
    if (account && account !== expectedAccount) { results.push({ token: t.purchaseToken, error: 'wrong account' }); continue; }
    // deno-lint-ignore no-explicit-any
    const item = (p.lineItems ?? []).find((l: any) => l.productId === t.productId) ?? p.lineItems?.[0];
    if (!item) { results.push({ token: t.purchaseToken, error: 'no line item' }); continue; }

    let acknowledged = p.acknowledgementState === 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED';
    if (!acknowledged && p.subscriptionState === 'SUBSCRIPTION_STATE_ACTIVE') {
      await client.request({
        url: `${base}/${encodeURIComponent(item.productId)}/tokens/${encodeURIComponent(t.purchaseToken)}:acknowledge`,
        method: 'POST', data: {},
      });
      acknowledged = true;
    }
    const { data, error } = await sb.rpc('play_record_purchase', {
      p_user_id: c.user.id, p_product_id: item.productId, p_purchase_token: t.purchaseToken,
      p_google_order_id: p.latestOrderId ?? null, p_state: p.subscriptionState,
      p_expiry: item.expiryTime ?? new Date().toISOString(), p_acknowledged: acknowledged,
    });
    results.push(error ? { token: t.purchaseToken, error: error.message } : { token: t.purchaseToken, ...data });
  }
  return json({ results });
});
