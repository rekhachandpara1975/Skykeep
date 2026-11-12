import type { Metadata } from 'next';
import { supabasePublic } from '@/lib/supabase/server';
import { rupees, durationLabel } from '@/lib/format';
import { APP_NAME } from '@/lib/site';
import { BuyButton } from './buy-button';

// Shown inside the direct/ads app WebView. No payment happens on this page.
export const metadata: Metadata = { title: 'Premium', robots: { index: false, follow: false } };
export const dynamic = 'force-dynamic';

type SP = { app?: string; free?: string; paused?: string };

export default async function Subscribe({ searchParams }: { searchParams: Promise<SP> }) {
  const sp = await searchParams;
  const freeIds = new Set((sp.free ?? '').split(',').filter(Boolean));
  const paused = sp.paused === '1';
  const sb = supabasePublic();
  const [{ data: plans = [] }, { data: offers }] = await Promise.all([
    sb.from('plans').select('id,name,price_inr,duration_days,perks,badge').eq('active', true).order('position'),
    sb.rpc('plan_offers'),
  ]);
  const payee: string | null = offers?.payee_name ?? null;

  return (
    <main className="min-h-screen bg-night px-4 py-6 text-slate-100">
      <h1 className="text-center text-2xl font-bold">{APP_NAME} <span className="text-amber-300">Premium</span></h1>
      <p className="mt-1 text-center text-sm text-slate-300">2 TB cloud storage · full videos · downloads</p>
      {paused && <p role="status" className="mx-auto mt-4 max-w-md rounded-xl border border-amber-400/40 bg-amber-400/10 p-3 text-center text-sm text-amber-200">Payments are paused right now. Please check back soon.</p>}
      <div className="mx-auto mt-6 max-w-md space-y-3">
        {(plans ?? []).map((p) => {
          const free = freeIds.has(p.id);
          return (
            <div key={p.id} className="rounded-2xl border border-white/10 bg-night-2 p-4">
              <div className="flex items-center justify-between gap-2">
                <h2 className="text-lg font-semibold">{p.name}</h2>
                {free ? <span className="badge bg-emerald-400/20 text-emerald-300">FREE</span> : p.badge && <span className="badge bg-amber-400/20 text-amber-300">{p.badge}</span>}
              </div>
              <p className="mt-1"><span className={`text-2xl font-bold ${free ? 'text-slate-500 line-through' : ''}`}>{rupees(p.price_inr)}</span>
                <span className="ml-2 text-sm text-slate-400">{durationLabel(p.duration_days).slice(2)}</span></p>
              <ul className="mt-2 space-y-1 text-sm text-slate-300">{p.perks.map((x: string) => <li key={x}>✓ {x}</li>)}</ul>
              <BuyButton planId={p.id} label={free ? 'Activate for free' : `Pay ${rupees(p.price_inr)} with UPI`} disabled={paused && !free} price={p.price_inr} />
              {!free && payee && <p className="mt-2 text-center text-xs text-slate-400">You will pay {rupees(p.price_inr)} to <b className="text-slate-200">{payee}</b> from your UPI app.</p>}
            </div>
          );
        })}
        {!plans?.length && <p className="text-center text-slate-400">No plans available right now.</p>}
      </div>
      <p className="mx-auto mt-6 max-w-md text-center text-xs text-slate-400">UPI only — no cards or wallets. After paying, your plan turns on once we verify the payment with the bank (usually within a few hours).</p>
      {sp.app !== '1' && <p className="mt-6 text-center text-sm text-slate-400">Open this page from the {APP_NAME} app to buy.</p>}
    </main>
  );
}
