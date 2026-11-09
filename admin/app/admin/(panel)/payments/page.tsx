import Link from 'next/link';
import { requireAdmin, supabaseServer } from '@/lib/supabase/server';
import { Submit } from '@/components/ui';
import { count, dateTime, paise, rupees } from '@/lib/format';
import { clearUpi, orderAction, savePaymentMode, saveUpi } from './actions';

const FILTERS = [['all', 'All'], ['verify_today', 'Activated today — verify against bank'], ['review', 'Needs review'],
  ['pending', 'Pending'], ['paid', 'Paid'], ['failed', 'Failed'], ['cancelled', 'Cancelled'], ['rejected', 'Rejected'], ['revoked', 'Revoked']];

type Order = { id: string; created_at: string; email: string | null; plan_name: string; amount_paise: number; reference: string;
  txn_id: string | null; utr: string | null; upi_id_used: string | null; status: string; raw_response: string | null;
  bank_verified: boolean; paid_at: string | null; admin_note: string | null };

const STATUS_COLOR: Record<string, string> = { paid: 'bg-emerald-100 text-emerald-700', review: 'bg-amber-100 text-amber-800',
  submitted: 'bg-amber-100 text-amber-800', pending: 'bg-slate-100 text-slate-700', failed: 'bg-red-100 text-red-700',
  rejected: 'bg-red-100 text-red-700', revoked: 'bg-red-100 text-red-700', cancelled: 'bg-slate-100 text-slate-500' };

export default async function Payments({ searchParams }: { searchParams: Promise<{ f?: string }> }) {
  await requireAdmin(true);
  const f = (await searchParams).f ?? 'all';
  const sb = await supabaseServer();
  const [{ data: ps }, { data: orders = [] }, { data: sales }, { data: audit = [] }, { data: stats }] = await Promise.all([
    sb.from('payment_settings').select('*').single(),
    sb.rpc('admin_orders', { p_filter: f, p_limit: 300 }),
    sb.rpc('admin_sales'),
    sb.from('settings_audit').select('*').order('changed_at', { ascending: false }).limit(50),
    sb.rpc('admin_stats'),
  ]);
  const live = !!(ps?.enabled && ps?.upi_id && ps?.payee_name);

  return (
    <>
      <h1 className="h1">Payments</h1>
      <div className="mb-6 grid gap-4 lg:grid-cols-2">
        <section className="card">
          <div className="mb-2 flex items-center justify-between">
            <h2 className="h2 mb-0">UPI settings</h2>
            <span className={`badge ${live ? 'bg-emerald-100 text-emerald-700' : 'bg-red-100 text-red-700'}`}>{live ? 'Payments live' : 'Payments off'}</span>
          </div>
          <p className="mb-3 text-sm">Current: <b>{ps?.upi_id ?? 'no UPI ID'}</b> · {ps?.payee_name ?? 'no payee name'}</p>
          <form action={saveUpi} className="grid gap-2 sm:grid-cols-2">
            <div><label className="label" htmlFor="upi">UPI ID (name@bank)</label>
              <input id="upi" name="upi_id" className="input" required pattern="[A-Za-z0-9._\-]{2,255}@[A-Za-z][A-Za-z0-9]{1,63}" defaultValue={ps?.upi_id ?? ''} /></div>
            <div><label className="label" htmlFor="payee">Payee name (exactly as your bank shows it)</label>
              <input id="payee" name="payee_name" className="input" required maxLength={100} defaultValue={ps?.payee_name ?? ''} /></div>
            <div className="flex gap-2 sm:col-span-2">
              <Submit confirm="New payments will go to the UPI ID you entered. Pending orders for the old UPI ID will be cancelled. Continue?">Save UPI</Submit>
            </div>
          </form>
          <form action={clearUpi} className="mt-2"><Submit className="btn-danger" confirm="Clear the UPI ID? Payments will turn OFF in the app immediately.">Clear UPI ID</Submit></form>
        </section>
        <section className="card">
          <h2 className="h2">Activation mode</h2>
          <form action={savePaymentMode} className="space-y-2 text-sm">
            <label className="flex gap-2"><input type="radio" name="activation_mode" value="instant" defaultChecked={ps?.activation_mode !== 'manual'} />
              <span><b>Instant</b> — a valid UPI SUCCESS (right reference, new transaction id, under 2 h) activates the plan at once. After 3 automatic activations for one user in 24 h, the next goes to review. Check your bank daily.</span></label>
            <label className="flex gap-2"><input type="radio" name="activation_mode" value="manual" defaultChecked={ps?.activation_mode === 'manual'} />
              <span><b>Manual</b> — every reported payment goes to review; you approve after you see it in your bank.</span></label>
            <label className="flex items-center gap-2"><input type="checkbox" name="enabled" defaultChecked={ps?.enabled} /> Payments enabled</label>
            <Submit>Save mode</Submit>
          </form>
        </section>
      </div>

      <div className="mb-4 grid grid-cols-2 gap-3 sm:grid-cols-4">
        {[['Revenue today', rupees(stats?.revenue_today)], ['Revenue this month', rupees(stats?.revenue_month)],
          ['To verify today', count(stats?.verify_today)], ['In review', count(stats?.review_orders)]].map(([l, v]) => (
          <div key={l} className="card"><p className="text-xs text-muted">{l}</p><p className="mt-1 text-xl font-semibold">{v}</p></div>))}
      </div>

      <div className="mb-3 flex flex-wrap gap-1">
        {FILTERS.map(([k, l]) => <Link key={k} href={`/admin/payments?f=${k}`} className={k === f ? 'btn-primary' : 'btn-ghost'}>{l}</Link>)}
      </div>
      <div className="card mb-6 overflow-x-auto">
        <table className="table">
          <thead><tr><th>Date</th><th>User</th><th>Plan</th><th>Amount</th><th>Reference</th><th>UTR / txn id</th><th>UPI ID used</th><th>Status</th><th>Actions</th></tr></thead>
          <tbody>
            {((orders ?? []) as Order[]).map((o) => (
              <tr key={o.id}>
                <td className="whitespace-nowrap text-xs">{dateTime(o.created_at)}</td>
                <td className="text-xs">{o.email ?? 'deleted user'}</td>
                <td>{o.plan_name}</td><td className="whitespace-nowrap">{paise(o.amount_paise)}</td>
                <td className="font-mono text-xs">{o.reference}</td>
                <td className="font-mono text-xs">{o.utr ?? o.txn_id ?? '—'}</td>
                <td className="text-xs">{o.upi_id_used}</td>
                <td><span className={`badge ${STATUS_COLOR[o.status] ?? ''}`}>{o.status}</span>{o.bank_verified && <span className="badge ml-1 bg-emerald-50 text-emerald-700">bank ✓</span>}
                  {(o.raw_response || o.admin_note) && <details className="mt-1 text-xs"><summary className="cursor-pointer text-muted">Details</summary>
                    {o.raw_response && <pre className="max-w-xs whitespace-pre-wrap break-all">{o.raw_response}</pre>}{o.admin_note && <p>Note: {o.admin_note}</p>}</details>}</td>
                <td className="min-w-48">
                  <form action={orderAction} className="flex flex-wrap gap-1">
                    <input type="hidden" name="id" value={o.id} /><input type="hidden" name="f" value={f} />
                    {['pending', 'submitted', 'review', 'failed'].includes(o.status) && <>
                      {o.status === 'review' && o.txn_id && <Submit name="op" value="approve" className="btn-success" confirm={`Approve ${o.reference}? Check it is in your bank first.`}>Approve</Submit>}
                      <input name="utr" className="input w-32" placeholder="12-digit UTR" pattern="[0-9]{12}" aria-label="UTR" />
                      <Submit name="op" value="mark_paid" className="btn-success" confirm={`Mark ${o.reference} as paid?`}>Mark paid</Submit>
                      <Submit name="op" value="reject" className="btn-danger" confirm={`Reject ${o.reference}?`}>Reject</Submit>
                    </>}
                    {o.status === 'paid' && <>
                      {!o.bank_verified && <Submit name="op" value="bank" className="btn-ghost">Bank verified</Submit>}
                      <Submit name="op" value="revoke" className="btn-danger" confirm={`Revoke ${o.reference}? The user's plan ends now.`}>Revoke</Submit>
                    </>}
                  </form>
                </td>
              </tr>
            ))}
            {!orders?.length && <tr><td colSpan={9} className="text-muted">No orders.</td></tr>}
          </tbody>
        </table>
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <section className="card overflow-x-auto"><h2 className="h2">Sales per plan</h2>
          <table className="table"><thead><tr><th>Plan</th><th className="text-right">Paid orders</th><th className="text-right">Revenue</th></tr></thead>
            <tbody>{(sales?.per_plan ?? []).map((r: { name: string; orders: number; revenue: number }) => (
              <tr key={r.name}><td>{r.name}</td><td className="text-right">{count(r.orders)}</td><td className="text-right">{rupees(r.revenue)}</td></tr>))}</tbody></table>
        </section>
        <section className="card overflow-x-auto"><h2 className="h2">Repeat buyers</h2>
          <table className="table"><thead><tr><th>User</th><th className="text-right">Orders</th><th className="text-right">Total</th></tr></thead>
            <tbody>{(sales?.repeat_buyers ?? []).map((r: { email: string; orders: number; total: number }) => (
              <tr key={r.email}><td className="text-xs">{r.email}</td><td className="text-right">{r.orders}</td><td className="text-right">{rupees(r.total)}</td></tr>))}
              {!sales?.repeat_buyers?.length && <tr><td colSpan={3} className="text-muted">None yet.</td></tr>}</tbody></table>
        </section>
      </div>

      <section className="card mt-6 overflow-x-auto"><h2 className="h2">Change history</h2>
        <table className="table"><thead><tr><th>When</th><th>What</th><th>Field</th><th>Old → New</th></tr></thead>
          <tbody>{(audit ?? []).map((a) => (
            <tr key={a.id}><td className="whitespace-nowrap text-xs">{dateTime(a.changed_at)}</td><td className="text-xs">{a.table_name} {a.row_ref && a.row_ref !== 'true' ? `(${a.row_ref})` : ''}</td>
              <td className="text-xs">{a.field}</td><td className="break-all text-xs">{a.old_value ?? '∅'} → <b>{a.new_value ?? '∅'}</b></td></tr>))}</tbody></table>
      </section>
    </>
  );
}
