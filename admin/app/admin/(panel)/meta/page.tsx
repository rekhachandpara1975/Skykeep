import { requireAdmin, supabaseServer } from '@/lib/supabase/server';
import { run, str, bool } from '@/lib/action';
import { Submit } from '@/components/ui';
import { count, dateTime } from '@/lib/format';
import { ADS_APK_URL } from '@/lib/site';

async function save(f: FormData) {
  'use server';
  await requireAdmin(true);
  await run('/admin/meta', 'Meta settings saved', async () => {
    const sb = await supabaseServer();
    const token = str(f, 'capi_token');
    if (token) { const r = await sb.rpc('set_meta_token', { p_token: token }); if (r.error) return r; }
    return sb.from('meta_settings').update({ pixel_id: str(f, 'pixel_id') || null, test_code: str(f, 'test_code') || null, enabled: bool(f, 'enabled') }).eq('id', true);
  });
}
async function test() {
  'use server';
  await requireAdmin(true);
  await run('/admin/meta', 'Test event sent — check Events Manager › Test events', async () => {
    const { error } = await (await supabaseServer()).functions.invoke('meta-send', { body: { test: true } });
    return { error: error ? { message: error.message } : null };
  });
}

export default async function Meta() {
  await requireAdmin(true);
  const sb = await supabaseServer();
  const [{ data: m }, { data: masked }, { data: q }] = await Promise.all([
    sb.from('meta_settings').select('*').single(),
    sb.rpc('meta_token_masked'),
    sb.from('meta_events').select('status'),
  ]);
  const by = (s: string) => (q ?? []).filter((e) => e.status === s).length;
  const apk = ADS_APK_URL;
  const healthy = m?.enabled && m?.last_success_at && !m?.last_error;

  return (
    <>
      <h1 className="h1">Meta Pixel</h1>
      <div className="grid gap-4 lg:grid-cols-2">
        <form action={save} className="card space-y-3">
          <div className="flex items-center justify-between"><h2 className="h2 mb-0">Pixel & Conversions API</h2>
            <span className={`badge ${healthy ? 'bg-emerald-100 text-emerald-700' : m?.last_error ? 'bg-red-100 text-red-700' : 'bg-slate-100 text-slate-700'}`}>{healthy ? 'Healthy' : m?.last_error ? 'Error' : 'Not sending yet'}</span></div>
          <div><label className="label" htmlFor="pixel">Pixel ID</label><input id="pixel" name="pixel_id" className="input" pattern="[0-9]{5,20}" defaultValue={m?.pixel_id ?? ''} /></div>
          <div><label className="label" htmlFor="tok">Conversions API token {masked && <span className="text-muted">(saved: {masked})</span>}</label>
            <input id="tok" name="capi_token" type="password" autoComplete="off" className="input" placeholder={masked ? 'Leave empty to keep' : 'Paste token'} /></div>
          <div><label className="label" htmlFor="tc">Test event code</label><input id="tc" name="test_code" className="input" defaultValue={m?.test_code ?? ''} /></div>
          <label className="flex items-center gap-2 text-sm"><input type="checkbox" name="enabled" defaultChecked={m?.enabled} /> Send events</label>
          <p className="text-xs text-muted">Last success: {dateTime(m?.last_success_at)}{m?.last_error && <> · Last error: <span className="text-red-700">{m.last_error}</span></>}</p>
          <p className="text-xs text-muted">Queue: {count(by('queued'))} queued · {count(by('sent'))} sent · {count(by('failed'))} failed</p>
          <Submit>Save</Submit>
        </form>
        <div className="space-y-4">
          <form action={test} className="card"><h2 className="h2">Send test event</h2><p className="mb-2 text-sm text-muted">Sends a Lead event with your test code.</p><Submit className="btn-ghost">Send test event</Submit></form>
          <div className="card space-y-2">
            <h2 className="h2 mb-0">Ads APK</h2>
            <p className="text-sm text-muted">Every build on main publishes the newest ads APK automatically; the /d page links to it.</p>
            <p className="break-all text-xs">Public link: <a className="text-accent underline" href={apk}>{apk}</a></p>
          </div>
        </div>
      </div>
    </>
  );
}
