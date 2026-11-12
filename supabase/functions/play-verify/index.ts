// Play build: verifies a Play Integrity token and grants 15 GB free cloud. Never enables UPI.
// Secrets: GOOGLE_SERVICE_ACCOUNT_JSON, PLAY_PACKAGE (com.skykeep.play)
import { GoogleAuth } from 'npm:google-auth-library@9.14.1';
import { admin, caller, json, serve } from '../_shared/util.ts';

serve(async (req) => {
  const c = await caller(req);
  if (!c) return json({ error: 'unauthorized' }, 401);
  const { token, nonce } = await req.json();
  if (typeof token !== 'string' || typeof nonce !== 'string') return json({ error: 'token and nonce required' }, 400);
  const sa = Deno.env.get('GOOGLE_SERVICE_ACCOUNT_JSON');
  const pkg = Deno.env.get('PLAY_PACKAGE') ?? 'com.skykeep.play';
  if (!sa) return json({ error: 'play verification not configured' }, 503);

  const auth = new GoogleAuth({ credentials: JSON.parse(sa), scopes: ['https://www.googleapis.com/auth/playintegrity'] });
  const client = await auth.getClient();
  // deno-lint-ignore no-explicit-any
  const res = await client.request<{ tokenPayloadExternal: any }>({
    url: `https://playintegrity.googleapis.com/v1/${pkg}:decodeIntegrityToken`,
    method: 'POST',
    data: { integrity_token: token },
  });
  const p = res.data.tokenPayloadExternal ?? {};
  const okNonce = p.requestDetails?.nonce === nonce || p.requestDetails?.requestHash === nonce;
  const okApp = p.appIntegrity?.appRecognitionVerdict === 'PLAY_RECOGNIZED' && p.appIntegrity?.packageName === pkg;
  const okDevice = (p.deviceIntegrity?.deviceRecognitionVerdict ?? []).includes('MEETS_DEVICE_INTEGRITY');
  if (!okNonce || !okApp || !okDevice) return json({ verified: false });
  const { data, error } = await admin().rpc('enable_play_free_cloud', { p_user_id: c.user.id, p_nonce: nonce });
  if (error) throw error;
  return json({ verified: Boolean(data) });
});
