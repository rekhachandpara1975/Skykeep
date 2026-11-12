// Sends queued Meta Conversions API events (Lead / CompleteRegistration / Purchase) with hashed user data.
// Called by cron with the service role key, or by the owner with {test:true} to send a test event.
import { admin, caller, isOwner, json, serve, sha256 } from '../_shared/util.ts';

const GRAPH = 'https://graph.facebook.com/v21.0';

serve(async (req) => {
  const sb = admin();
  const isCron = req.headers.get('Authorization') === `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`;
  let test = false;
  if (!isCron) {
    const c = await caller(req);
    if (!c || !(await isOwner(c.user.id))) return json({ error: 'forbidden' }, 403);
    test = Boolean((await req.json().catch(() => ({}))).test);
  }
  const { data: cfg } = await sb.rpc('meta_sender_config');
  if (!cfg?.pixel_id || !cfg?.token) return json({ skipped: 'pixel not configured' });
  if (!cfg.enabled && !test) return json({ skipped: 'disabled' });

  const send = async (data: unknown[]) => {
    const r = await fetch(`${GRAPH}/${cfg.pixel_id}/events?access_token=${encodeURIComponent(cfg.token)}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ data, ...(cfg.test_code ? { test_event_code: cfg.test_code } : {}) }),
    });
    const body = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(body?.error?.message ?? `HTTP ${r.status}`);
    return body;
  };

  if (test) {
    try {
      const res = await send([{
        event_name: 'Lead',
        event_time: Math.floor(Date.now() / 1000),
        action_source: 'app',
        event_id: `test_${crypto.randomUUID()}`,
        user_data: { external_id: [await sha256('test')] },
      }]);
      await sb.rpc('meta_mark', { p_ids: [], p_ok: true });
      return json({ ok: true, res });
    } catch (e) {
      await sb.rpc('meta_mark', { p_ids: [], p_ok: false, p_error: String(e) });
      return json({ ok: false, error: String(e) }, 502);
    }
  }

  const { data: rows } = await sb.rpc('meta_pending_events', { p_limit: 50 });
  if (!rows?.length) return json({ sent: 0 });
  // deno-lint-ignore no-explicit-any
  const data = await Promise.all(rows.map(async (e: any) => ({
    event_name: e.event_name,
    event_time: Math.floor(new Date(e.created_at).getTime() / 1000),
    event_id: e.event_id,
    action_source: 'app',
    user_data: {
      ...(e.email ? { em: [await sha256(e.email)] } : {}),
      ...(e.user_id ? { external_id: [await sha256(e.user_id)] } : {}),
    },
    ...(e.event_name === 'Purchase' ? { custom_data: { currency: 'INR', value: Number(e.value_inr) } } : {}),
  })));
  // deno-lint-ignore no-explicit-any
  const ids = rows.map((r: any) => r.id);
  try {
    await send(data);
    await sb.rpc('meta_mark', { p_ids: ids, p_ok: true });
    return json({ sent: ids.length });
  } catch (e) {
    await sb.rpc('meta_mark', { p_ids: ids, p_ok: false, p_error: String(e) });
    return json({ error: String(e) }, 502);
  }
});
