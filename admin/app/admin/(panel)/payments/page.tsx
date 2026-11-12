import Link from 'next/link';
import { requireAdmin, supabaseServer } from '@/lib/supabase/server';
import { Submit } from '@/components/ui';
import { count, dateTime, paise, rupees } from '@/lib/format';
import { clearUpi, orderAction, savePaymentMode, saveUpi } from './actions';

const FILTERS = [['review', 'To verify'], ['all', 'All'], ['verify_today', 'Paid today — bank not ticked'],
  ['pending', 'Waiting for payment'], ['expired', 'Expired'], ['paid', 'Paid'], ['failed', 'Failed'], ['cancelled', 'Cancelled'],
  ['rejected', 'Rejected'], ['revoked', 'Revoked']];

type Order = { id: string; created_at: string; email: string | null; plan_name: string; amount_paise: number; reference: string;
  txn_id: string | null; utr: string | null; utr_source: string | null; upi_id_used: string | null; status: string; raw_response: string | null;
  bank_verified: boolean; paid_at: string | null; admin_note: string | null; expires_at: string | null;
  proof_screenshot_key: string | null; proof_submitted_at: string | null };
type OrderEvent = { order_id: string; old_status: string | null; new_status: string; created_at: string; note: string | null };

const SOURCE: Record<string, string> = { upi_app: 'from UPI app', buyer: 'typed by buyer', admin: 'entered by you', provider: 'bank webhook' };

const STATUS_COLOR: Record<string, string> = { paid: 'bg-emerald-100 text-emerald-700', review: 'bg-amber-100 text-amber-800',
  submitted: 'bg-amber-100 text-amber-800', pending: 'bg-slate-100 text-slate-700', failed: 'bg-red-100 text-red-700',
  expired: 'bg-slate-100 text-slate-500',
  rejected: 'bg-red-100 text-red-700', revoked: 'bg-red-100 text-red-700', cancelled: 'bg-slate-100 text-slate-500' };

export default async function Payments({ searchParams }: { searchParams: Promise<{ f?: string }> }) {
  await requireAdmin(true);
  const f = (await searchParams).f ?? 'review';
  const sb = await supabaseServer();
  const [{ data: ps }, { data: orders = [] }, { data: sales }, { data: audit = [] }, { data: stats }, { data: credits = [] }] = await Promise.all([
    sb.from('payment_settings').select('*').single(),
    sb.rpc('admin_orders', { p_filter: f, p_limit: 300 }),
    sb.rpc('admin_sales'),
    sb.from('settings_audit').select('*').order('changed_at', { ascending: false }).limit(50),
    sb.rpc('admin_stats'),
    sb.rpc('admin_bank_credits', { p_limit: 20 }),
  ]);
  const smsUrl = `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/bank-sms`;
  const live = !!(ps?.enabled && ps?.upi_id && ps?.payee_name);
  const list = (orders ?? []) as Order[];
  const [{ data: events = [] }, shots] = await Promise.all([
    list.length ? sb.from('payment_order_events').select('order_id,old_status,new_status,created_at,note')
      .in('order_id', list.map((o) => o.id)).order('created_at') : Promise.resolve({ data: [] as OrderEvent[] }),
    Promise.all(list.filter((o) => o.proof_screenshot_key).map(async (o) => {
      const { data } = await sb.storage.from('payment-proofs').createSignedUrl(o.proof_screenshot_key!, 600);
      return [o.id, data?.signedUrl] as const;
    })),
  ]);
  const shotUrl = new Map(shots);
  const eventsFor = (id: string) => ((events ?? []) as OrderEvent[]).filter((e) => e.order_id === id);

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
          <h2 className="h2">How payments are verified</h2>
          <ol className="mb-3 list-decimal space-y-1 pl-5 text-sm">
            {ps?.activation_mode === 'instant' ? (<>
              <li>The buyer pays in their UPI app. When the app answers <b>SUCCESS</b> for that exact order (right reference, a new transaction id/UTR),
                the plan turns on <b>instantly</b>. At most 3 instant activations per buyer per day; more go to <b>To verify</b>.</li>
              <li>Every instant activation appears under <b>Activated today — verify against bank</b>. Find it in your bank → <b>Bank verified</b>. Not there → <b>Revoke</b>.</li>
            </>) : (<>
              <li>The buyer pays in their UPI app. The app&apos;s answer is only a hint — no plan is activated from the phone.</li>
              <li>Orders with a valid UPI answer, or a 12-digit UTR typed by the buyer (plus optional screenshot), appear under <b>To verify</b>.</li>
            </>)}
            <li>Find the credit in your bank (same amount + UTR) → <b>Approve</b>. Not there → <b>Reject</b>. No UTR yet → type it from your bank and <b>Mark paid</b>.</li>
            <li>Unpaid orders expire after 30 minutes. A buyer can still send proof for 24 hours.</li>
          </ol>
          <form action={savePaymentMode} className="flex flex-wrap items-center gap-3 text-sm">
            <label className="flex items-center gap-2"><input type="checkbox" name="enabled" defaultChecked={ps?.enabled} /> Payments enabled</label>
            <label className="flex items-center gap-2"><input type="checkbox" name="instant" defaultChecked={ps?.activation_mode === 'instant'} /> Activate instantly when the UPI app says SUCCESS</label>
            <Submit>Save</Submit>
          </form>
        </section>
      </div>

      <section className="card mb-6 overflow-x-auto">
        <div className="mb-2 flex items-center justify-between">
          <h2 className="h2 mb-0">Bank SMS auto-verify</h2>
          <span className={`badge ${credits?.length ? 'bg-emerald-100 text-emerald-700' : 'bg-slate-100 text-slate-600'}`}>
            {credits?.length ? `Last SMS ${dateTime(credits[0].received_at)}` : 'No bank SMS received yet'}</span>
        </div>
        <p className="mb-2 text-sm text-muted">
          When your bank texts a UPI credit, an SMS-forwarder app on that phone sends it here. A plan turns on automatically only when the
          bank&apos;s amount and UTR match an order (or the amount matches exactly one open order). Anything unclear stays under <b>To verify</b>.
        </p>
        <p className="mb-3 break-all rounded bg-slate-50 p-2 font-mono text-xs">{smsUrl}?key=YOUR_BANK_SMS_KEY</p>
        <table className="table">
          <thead><tr><th>Received</th><th>Amount</th><th>UTR</th><th>Matched order</th><th>Result</th></tr></thead>
          <tbody>
            {(credits ?? []).map((c: { id: number; received_at: string; amount_paise: number; utr: string | null; reference: string | null; order_status: string | null; note: string | null }) => (
              <tr key={c.id}>
                <td className="whitespace-nowrap text-xs">{dateTime(c.received_at)}</td>
                <td className="whitespace-nowrap">{paise(c.amount_paise)}</td>
                <td className="font-mono text-xs">{c.utr ?? '—'}</td>
                <td className="font-mono text-xs">{c.reference ?? '—'}{c.order_status && <span className={`badge ml-1 ${STATUS_COLOR[c.order_status] ?? ''}`}>{c.order_status}</span>}</td>
                <td className="text-xs">{c.note}</td>
              </tr>))}
            {!credits?.length && <tr><td colSpan={5} className="text-muted">Nothing yet. Set it up with docs/payments.md › Automatic verification.</td></tr>}
          </tbody>
        </table>
      </section>

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
          <thead><tr><th>Date</th><th>User</th><th>Plan</th><th>Amount</th><th>Reference</th><th>UTR / proof</th><th>UPI ID used</th><th>Status</th><th>Actions</th></tr></thead>
          <tbody>
            {list.map((o) => (
              <tr key={o.id}>
                <td className="whitespace-nowrap text-xs">{dateTime(o.created_at)}</td>
                <td className="text-xs">{o.email ?? 'deleted user'}</td>
                <td>{o.plan_name}</td><td className="whitespace-nowrap">{paise(o.amount_paise)}</td>
                <td className="font-mono text-xs">{o.reference}</td>
                <td className="text-xs"><span className="font-mono">{o.utr ?? o.txn_id ?? '—'}</span>
                  {o.utr && o.utr_source && <span className="block text-muted">{SOURCE[o.utr_source] ?? o.utr_source}</span>}
                  {shotUrl.get(o.id) && <a href={shotUrl.get(o.id)} target="_blank" rel="noopener noreferrer" className="block text-blue-700 underline">Screenshot</a>}</td>
                <td className="text-xs">{o.upi_id_used}</td>
                <td><span className={`badge ${STATUS_COLOR[o.status] ?? ''}`}>{o.status}</span>{o.bank_verified && <span className="badge ml-1 bg-emerald-50 text-emerald-700">bank ✓</span>}
                  <details className="mt-1 text-xs"><summary className="cursor-pointer text-muted">Details</summary>
                    {o.raw_response && <pre className="max-w-xs whitespace-pre-wrap break-all">{o.raw_response}</pre>}{o.admin_note && <p>Note: {o.admin_note}</p>}
                    <ul className="mt-1 space-y-0.5">{eventsFor(o.id).map((e, i) => (
                      <li key={i}>{dateTime(e.created_at)}: {e.old_status ?? 'new'} → <b>{e.new_status}</b>{e.note ? ` (${e.note})` : ''}</li>))}</ul></details></td>
                <td className="min-w-48">
                  <form action={orderAction} className="flex flex-wrap gap-1">
                    <input type="hidden" name="id" value={o.id} /><input type="hidden" name="f" value={f} />
                    {['pending', 'submitted', 'review', 'failed', 'expired'].includes(o.status) && <>
                      {['review', 'submitted', 'expired'].includes(o.status) && (o.utr || o.txn_id) && <Submit name="op" value="approve" className="btn-success" confirm={`Approve ${o.reference} (${paise(o.amount_paise)}, UTR ${o.utr ?? o.txn_id})? Check it is in your bank first.`}>Approve</Submit>}
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
            {!list.length && <tr><td colSpan={9} className="text-muted">No orders.</td></tr>}
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
