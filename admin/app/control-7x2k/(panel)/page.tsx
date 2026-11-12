import Link from 'next/link';
import { requireAdmin, supabaseServer } from '@/lib/supabase/server';
import { count, rupees } from '@/lib/format';

export default async function Dashboard() {
  const me = await requireAdmin();
  const sb = await supabaseServer();
  const { data: s, error } = await sb.rpc('admin_stats');
  if (error || !s) return <p className="error-alert text-red-700">Could not load stats: {error?.message}</p>;

  const alerts = [
    { n: s.channel_requests, text: 'channel requests waiting', href: '/control-7x2k/channels' },
    ...(me.role === 'owner' ? [
      { n: s.organic_waiting, text: 'organic buyers waiting for full access', href: '/control-7x2k/approvals' },
      { n: s.verify_today, text: 'payments activated today — verify against bank', href: '/control-7x2k/payments?f=verify_today' },
      { n: s.review_orders, text: 'payments in review', href: '/control-7x2k/payments?f=review' },
    ] : []),
  ].filter((a) => a.n > 0);

  const tiles = [
    ['Ads installs', count(s.ads_installs)], ['Organic installs', count(s.organic_installs)],
    ['Users', count(s.users)], ['Logged in', count(s.logged_in)], ['Premium users', count(s.premium_users)],
    ['Channels', count(s.channels)], ['Posts', count(s.posts)],
    ...(me.role === 'owner' ? [['Revenue today', rupees(s.revenue_today)], ['Revenue this month', rupees(s.revenue_month)],
      ['Free plans claimed', count(s.free_claims)]] : []),
  ];

  return (
    <>
      <h1 className="h1">Dashboard</h1>
      {alerts.length > 0 && (
        <div className="mb-4 space-y-2">
          {alerts.map((a) => (
            <Link key={a.href} href={a.href} className="flex items-center gap-2 rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 text-sm text-amber-900 hover:bg-amber-100">
              <span className="rounded-full bg-red-600 px-2 text-xs font-bold text-white">{a.n}</span> {a.text} →
            </Link>
          ))}
        </div>
      )}
      <div className="mb-6 grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
        {tiles.map(([label, v]) => (
          <div key={label} className="card"><p className="text-xs text-muted">{label}</p><p className="mt-1 text-xl font-semibold">{v}</p></div>
        ))}
      </div>
      <div className="card overflow-x-auto">
        <h2 className="h2">Installs by source / campaign</h2>
        <table className="table">
          <thead><tr><th>Source</th><th>Campaign</th><th className="text-right">Installs</th></tr></thead>
          <tbody>
            {(s.by_campaign as { source: string; campaign: string; installs: number }[]).map((r) => (
              <tr key={r.source + r.campaign}>
                <td><span className={`badge ${r.source === 'ads' ? 'bg-violet-100 text-violet-700' : 'bg-slate-100 text-slate-700'}`}>{r.source}</span></td>
                <td>{r.campaign}</td><td className="text-right">{count(r.installs)}</td>
              </tr>
            ))}
            {!s.by_campaign.length && <tr><td colSpan={3} className="text-muted">No installs yet.</td></tr>}
          </tbody>
        </table>
      </div>
    </>
  );
}
