import { requireAdmin, supabaseServer } from '@/lib/supabase/server';
import { run, str, num, bool } from '@/lib/action';
import { Submit } from '@/components/ui';
import { count, planLength, rupees } from '@/lib/format';
import { PlanCard } from './plan-card';

async function saveMode(f: FormData) {
  'use server';
  await requireAdmin(true);
  const patch: Record<string, unknown> = {};
  if (f.has('free_mode')) patch.free_mode = f.getAll('free_mode').includes('on');
  if (f.has('free_plans_for')) patch.free_plans_for = str(f, 'free_plans_for');
  if (f.has('plans_visible_for')) patch.plans_visible_for = str(f, 'plans_visible_for');
  await run('/admin/plans', 'Saved — the app updates live', async () => (await supabaseServer()).from('app_mode').update(patch).eq('id', true));
}

async function savePlan(f: FormData) {
  'use server';
  await requireAdmin(true);
  const id = str(f, 'id');
  const n = num(f, 'duration');
  const hours = str(f, 'duration_unit') === 'hours';
  const row = {
    name: str(f, 'name'), price_inr: num(f, 'price_inr'),
    duration_hours: hours ? n : null, duration_days: hours ? Math.max(1, Math.ceil(n / 24)) : n,
    perks: str(f, 'perks').split('\n').map((p) => p.trim()).filter(Boolean), badge: str(f, 'badge') || null,
    position: num(f, 'position'), active: bool(f, 'active'), free_eligible: bool(f, 'free_eligible'),
  };
  await run('/admin/plans', id ? 'Plan saved' : 'Plan added', async () => {
    const sb = await supabaseServer();
    return id ? sb.from('plans').update(row).eq('id', id) : sb.from('plans').insert({ ...row, code: str(f, 'code').toLowerCase() });
  });
}

const GROUPS = [['none', 'Off'], ['organic', 'Organic'], ['ads', 'Ads'], ['everyone', 'Everyone']];
const VIS = [['everyone', 'Everyone'], ['ads', 'Ads only'], ['organic', 'Organic only'], ['none', 'Nobody']];

export default async function Plans() {
  await requireAdmin(true);
  const sb = await supabaseServer();
  const [{ data: mode }, { data: plans = [] }, { data: sales }, { count: claims }] = await Promise.all([
    sb.from('app_mode').select('*').single(),
    sb.from('plans').select('*').order('position'),
    sb.rpc('admin_sales'),
    sb.from('free_plan_claims').select('*', { count: 'exact', head: true }),
  ]);
  const pc = (sales?.plan_counts ?? {}) as Record<string, { subscribers: number; orders: number }>;

  return (
    <>
      <h1 className="h1">Plans</h1>
      <div className="mb-6 grid gap-4 lg:grid-cols-3">
        <form action={saveMode} className="card space-y-2">
          <h2 className="h2 mb-0">Free mode</h2>
          <p className="text-sm text-muted">ON: no prices or payments anywhere; logged-in users get 15 GB; ads users get full access; organic users can request full access.</p>
          <input type="hidden" name="free_mode" value="off" />
          <label className="flex items-center gap-2 text-sm"><input type="checkbox" name="free_mode" defaultChecked={mode?.free_mode} /> Free mode is ON</label>
          <Submit confirm="Change free mode? Every app updates immediately.">Save</Submit>
        </form>
        <form action={saveMode} className="card space-y-2">
          <h2 className="h2 mb-0">Free plans</h2>
          <p className="text-sm text-muted">Plans marked “Free when free plans are on” can be claimed once per promotion. {count(claims)} claimed so far.</p>
          <div className="flex flex-wrap gap-2">{GROUPS.map(([v, l]) => (
            <label key={v} className="flex items-center gap-1 text-sm"><input type="radio" name="free_plans_for" value={v} defaultChecked={mode?.free_plans_for === v} /> {l}</label>))}</div>
          <Submit>Save</Submit>
        </form>
        <form action={saveMode} className="card space-y-2">
          <h2 className="h2 mb-0">Show plans in app</h2>
          <p className="text-sm text-muted">Hidden users see no crown, no prices and cannot buy. Existing subscribers still see their plan.</p>
          <div className="flex flex-wrap gap-2">{VIS.map(([v, l]) => (
            <label key={v} className="flex items-center gap-1 text-sm"><input type="radio" name="plans_visible_for" value={v} defaultChecked={mode?.plans_visible_for === v} /> {l}</label>))}</div>
          <Submit>Save</Submit>
        </form>
      </div>

      <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
        {(plans ?? []).map((p) => (
          <PlanCard key={p.id} plan={p} action={savePlan} freeOn={mode?.free_plans_for !== 'none'}
            stats={pc[p.id] ?? { subscribers: 0, orders: 0 }} priceLabel={rupees(p.price_inr)} durationHint={planLength(p)} />
        ))}
        <form action={savePlan} className="card space-y-2 border-dashed">
          <h2 className="h2 mb-0">Add plan</h2>
          <div className="grid grid-cols-2 gap-2">
            <div><label className="label" htmlFor="n-code">Code (permanent)</label><input id="n-code" name="code" className="input" required pattern="[a-z0-9_\-]{2,40}" placeholder="monthly" /></div>
            <div><label className="label" htmlFor="n-name">Name</label><input id="n-name" name="name" className="input" required /></div>
            <div><label className="label" htmlFor="n-price">Price ₹</label><input id="n-price" name="price_inr" type="number" min={1} step={1} className="input" required /></div>
            <div><label className="label" htmlFor="n-days">Duration</label>
              <div className="flex gap-1"><input id="n-days" name="duration" type="number" min={1} max={8784} className="input" required defaultValue={30} />
                <select name="duration_unit" aria-label="Duration unit" className="input w-28" defaultValue="days"><option value="days">days</option><option value="hours">hours</option></select></div></div>
            <div><label className="label" htmlFor="n-badge">Badge</label><input id="n-badge" name="badge" className="input" placeholder="Best value" /></div>
            <div><label className="label" htmlFor="n-pos">Order</label><input id="n-pos" name="position" type="number" className="input" defaultValue={(plans?.length ?? 0) + 1} /></div>
          </div>
          <div><label className="label" htmlFor="n-perks">Perks (one per line)</label><textarea id="n-perks" name="perks" rows={3} className="input" defaultValue={'2 TB cloud storage\nFull videos\nDownloads'} /></div>
          <label className="flex items-center gap-2 text-sm"><input type="checkbox" name="active" defaultChecked /> Show in app</label>
          <label className="flex items-center gap-2 text-sm"><input type="checkbox" name="free_eligible" /> Free when free plans are on</label>
          <Submit>Add plan</Submit>
        </form>
      </div>
    </>
  );
}
