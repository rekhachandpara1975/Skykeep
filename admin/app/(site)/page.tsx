import Link from 'next/link';
import { supabasePublic } from '@/lib/supabase/server';
import { rupees, durationLabel } from '@/lib/format';
import { APP_NAME, SUPPORT_EMAIL } from '@/lib/site';

export const revalidate = 60;

const FAQ = [
  ['Is the 15 GB really free?', 'Yes. Create a free account and you get 15 GB of private cloud storage when free storage is on. Premium raises it to 2 TB.'],
  ['How do I pay?', 'Inside the app with any UPI app (GPay, PhonePe, Paytm, BHIM and more). There is no card form and we never see your bank details.'],
  ['Who can see my files?', 'Only you. Files are stored in private buckets and opened with short-lived signed links.'],
  ['Are channels moderated?', 'Every new channel is reviewed before it goes live, and anyone can report a post or channel in one tap.'],
  ['How do I delete my account?', 'In the app: Profile › Settings › Delete account. Or use the form on our delete-account page.'],
];

export default async function Home() {
  const sb = supabasePublic();
  const [{ data: mode }, { data: plans = [] }] = await Promise.all([
    sb.from('app_mode').select('free_mode').single(),
    sb.from('plans').select('id,name,price_inr,duration_days,perks,badge').eq('active', true).order('position'),
  ]);
  const free = mode?.free_mode ?? false;

  return (
    <main className="mx-auto max-w-5xl px-4">
      <section className="py-16 text-center">
        <h1 className="text-4xl font-bold leading-tight sm:text-5xl">Your files, safe in the sky.<br /><span className="bg-gradient-to-r from-accent to-accent-2 bg-clip-text text-transparent">Channels you can trust.</span></h1>
        <p className="mx-auto mt-4 max-w-xl text-slate-300">{APP_NAME} gives you 15 GB of free private cloud storage, up to 2 TB with Premium, and creator channels reviewed by people.</p>
        <Link href="/d" className="gradient mt-8 inline-block rounded-xl px-6 py-3 font-semibold text-white">Download for Android</Link>
      </section>

      <section className="grid gap-4 sm:grid-cols-3">
        {[['15 GB free', 'Photos, videos and files backed up privately. Folders, rename, move — everything you expect.'],
          ['2 TB Premium', 'Room for your whole phone history, full-length videos and downloads.'],
          ['Private by default', 'Private storage, signed links that expire, and no ad trackers in the app.']].map(([t, d]) => (
          <div key={t} className="rounded-2xl border border-white/10 bg-night-2 p-5"><h2 className="text-lg font-semibold">{t}</h2><p className="mt-2 text-sm text-slate-300">{d}</p></div>))}
      </section>

      <section className="mt-12 rounded-2xl border border-white/10 bg-night-2 p-6">
        <h2 className="text-2xl font-semibold">Channels & safety</h2>
        <p className="mt-2 text-slate-300">Follow creators, watch trailers and full videos. New channels are approved by our team, posts follow our community rules, and you can report or block any channel in one tap.</p>
      </section>

      <section id="plans" className="mt-12">
        {free ? (
          <div className="rounded-2xl border border-accent/40 bg-accent/10 p-6 text-center">
            <h2 className="text-2xl font-semibold">Free right now</h2>
            <p className="mt-2 text-slate-300">Log in to the app and get 15 GB of cloud storage free. No payment needed.</p>
          </div>
        ) : (
          <>
            <h2 className="mb-4 text-2xl font-semibold">Plans</h2>
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
              {(plans ?? []).map((p) => (
                <div key={p.id} className="rounded-2xl border border-white/10 bg-night-2 p-5">
                  <div className="flex items-center justify-between"><h3 className="text-lg font-semibold">{p.name}</h3>{p.badge && <span className="badge bg-amber-400/20 text-amber-300">{p.badge}</span>}</div>
                  <p className="mt-2 text-3xl font-bold">{rupees(p.price_inr)}</p><p className="text-sm text-slate-400">{durationLabel(p.duration_days).slice(2)}</p>
                  <ul className="mt-3 space-y-1 text-sm text-slate-300">{p.perks.map((x: string) => <li key={x}>✓ {x}</li>)}</ul>
                </div>))}
              {!plans?.length && <p className="text-slate-400">Plans are coming soon.</p>}
            </div>
            <p className="mt-3 text-sm text-slate-400">Buy inside the app with any UPI app.</p>
          </>
        )}
      </section>

      <section id="faq" className="mt-12">
        <h2 className="mb-4 text-2xl font-semibold">FAQ</h2>
        <div className="space-y-2">{FAQ.map(([q, a]) => (
          <details key={q} className="rounded-xl border border-white/10 bg-night-2 p-4"><summary className="cursor-pointer font-medium">{q}</summary><p className="mt-2 text-sm text-slate-300">{a}</p></details>))}
        </div>
        <p className="mt-4 text-sm text-slate-400">Still stuck? Email <a className="underline" href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a>.</p>
      </section>
    </main>
  );
}
