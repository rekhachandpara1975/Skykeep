import { requireAdmin, supabaseServer } from '@/lib/supabase/server';
import { run, str, bool } from '@/lib/action';
import { Submit } from '@/components/ui';
import { count } from '@/lib/format';

async function saveFlags(f: FormData) {
  'use server';
  await requireAdmin(true);
  const approved = bool(f, 'google_approval_confirmed');
  const enabled = approved && bool(f, 'play_billing_enabled');
  await run('/admin/play', enabled ? 'Play billing is ON — Play builds update live' : 'Saved — Play billing is off', async () =>
    (await supabaseServer()).from('play_settings')
      .update({ google_approval_confirmed: approved, play_billing_enabled: enabled }).eq('id', true));
}

async function saveProduct(f: FormData) {
  'use server';
  await requireAdmin(true);
  const row = {
    product_id: str(f, 'product_id'), base_plan_id: str(f, 'base_plan_id') || null,
    plan_id: str(f, 'plan_id'), active: bool(f, 'active'),
  };
  await run('/admin/play', 'Play product saved', async () =>
    (await supabaseServer()).from('play_products').upsert(row, { onConflict: 'product_id' }));
}

export default async function Play() {
  await requireAdmin(true);
  const sb = await supabaseServer();
  const [{ data: s }, { data: products = [] }, { data: plans = [] }, { data: o }] = await Promise.all([
    sb.from('play_settings').select('*').single(),
    sb.from('play_products').select('*').order('created_at'),
    sb.from('plans').select('id,name,code,active').order('position'),
    sb.rpc('admin_play_overview'),
  ]);
  const on = Boolean(s?.play_billing_enabled && s?.google_approval_confirmed);
  const planName = (id: string) => plans?.find((p) => p.id === id)?.name ?? '—';
  const steps: [string, boolean][] = [
    ['Google approved User Choice Billing (India) for com.skykeep.play', Boolean(s?.google_approval_confirmed)],
    ['At least one Play subscription mapped to a plan', (o?.products ?? 0) > 0],
    ['Secrets GOOGLE_SERVICE_ACCOUNT_JSON + PLAY_PACKAGE added in Supabase (see docs/play-billing.md)', (o?.google_purchases ?? 0) > 0 || (o?.upi_choice_orders ?? 0) > 0],
    ['Hourly play-report cron job created', !o?.reports_overdue],
  ];

  return (
    <>
      <h1 className="h1">Google Play billing</h1>
      <p className="mb-4 max-w-3xl text-sm text-muted">
        Play builds never show your UPI page. While this is off, Play users get the free tier only (15 GB after the Play Integrity check)
        and see “Premium members only”. Turn it on only after Google approves User Choice Billing — then Google shows
        “Pay with Google Play” or “Pay with UPI” on every purchase.
      </p>

      <div className="mb-6 grid gap-4 lg:grid-cols-2">
        <form action={saveFlags} className="card space-y-3">
          <div className="flex items-center justify-between">
            <h2 className="h2 mb-0">Status</h2>
            <span className={`rounded-full px-2 py-0.5 text-xs font-semibold ${on ? 'bg-emerald-100 text-emerald-700' : 'bg-slate-100 text-slate-600'}`}>
              {on ? 'Play billing ON' : 'Play billing OFF'}
            </span>
          </div>
          <label className="flex items-start gap-2 text-sm">
            <input type="checkbox" name="google_approval_confirmed" defaultChecked={s?.google_approval_confirmed} className="mt-1" />
            <span>I confirm Google approved User Choice Billing for this app in Play Console.</span>
          </label>
          <label className={`flex items-start gap-2 text-sm ${s?.google_approval_confirmed ? '' : 'opacity-50'}`}>
            <input type="checkbox" name="play_billing_enabled" defaultChecked={s?.play_billing_enabled} disabled={!s?.google_approval_confirmed} className="mt-1" />
            <span>Turn on purchases in the Play build {s?.google_approval_confirmed ? '' : '(confirm approval and save first)'}</span>
          </label>
          <Submit confirm="Change Google Play billing? Every Play install updates immediately.">Save</Submit>
        </form>

        <div className="card">
          <h2 className="h2">Setup checklist</h2>
          <ul className="space-y-2 text-sm">
            {steps.map(([label, done]) => (
              <li key={label} className="flex gap-2"><span aria-hidden>{done ? '✅' : '⬜'}</span><span>{label}</span></li>
            ))}
          </ul>
          <dl className="mt-4 grid grid-cols-2 gap-2 text-sm">
            <dt className="text-muted">Google Play purchases</dt><dd>{count(o?.google_purchases ?? 0)}</dd>
            <dt className="text-muted">UPI-choice orders</dt><dd>{count(o?.upi_choice_orders ?? 0)}</dd>
            <dt className="text-muted">Reports to Google waiting</dt><dd>{count(o?.reports_waiting ?? 0)}</dd>
            <dt className="text-muted">Overdue (&gt;20 h)</dt><dd className={(o?.reports_overdue ?? 0) > 0 ? 'font-semibold text-red-600' : ''}>{count(o?.reports_overdue ?? 0)}</dd>
          </dl>
          {o?.last_report_error && <p className="mt-2 break-all text-xs text-red-600">Last report error: {o.last_report_error}</p>}
        </div>
      </div>

      <div className="card overflow-x-auto">
        <h2 className="h2">Play subscriptions → plans</h2>
        <p className="mb-3 text-sm text-muted">Create the subscription and base plan in Play Console first, then map it here. Prices are set in Play Console.</p>
        <table className="w-full text-sm">
          <thead><tr className="text-left text-muted"><th className="py-2">Product id</th><th>Base plan</th><th>Plan</th><th>Active</th><th /></tr></thead>
          <tbody>
            {(products ?? []).map((p) => (
              <tr key={p.product_id} className="border-t">
                <td colSpan={5} className="py-2">
                  <form action={saveProduct} className="grid grid-cols-2 items-center gap-2 md:grid-cols-5">
                    <input name="product_id" defaultValue={p.product_id} readOnly className="input bg-slate-50" aria-label="Product id" />
                    <input name="base_plan_id" defaultValue={p.base_plan_id ?? ''} className="input" aria-label="Base plan id" />
                    <select name="plan_id" defaultValue={p.plan_id} className="input" aria-label="Plan">
                      {(plans ?? []).map((pl) => <option key={pl.id} value={pl.id}>{pl.name}</option>)}
                    </select>
                    <label className="flex items-center gap-2"><input type="checkbox" name="active" defaultChecked={p.active} /> {planName(p.plan_id)}</label>
                    <Submit className="btn-ghost">Save</Submit>
                  </form>
                </td>
              </tr>
            ))}
            <tr className="border-t">
              <td colSpan={5} className="py-2">
                <form action={saveProduct} className="grid grid-cols-2 items-center gap-2 md:grid-cols-5">
                  <input name="product_id" required pattern="[a-z0-9._]{1,100}" placeholder="skykeep_monthly" className="input" aria-label="New product id" />
                  <input name="base_plan_id" placeholder="monthly" className="input" aria-label="New base plan id" />
                  <select name="plan_id" className="input" aria-label="New plan" required>
                    {(plans ?? []).map((pl) => <option key={pl.id} value={pl.id}>{pl.name}</option>)}
                  </select>
                  <label className="flex items-center gap-2"><input type="checkbox" name="active" defaultChecked /> Active</label>
                  <Submit>Add mapping</Submit>
                </form>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </>
  );
}
