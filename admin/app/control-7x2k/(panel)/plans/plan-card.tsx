'use client';
import { useRef } from 'react';

type Plan = { id: string; code: string; name: string; price_inr: number; duration_days: number; duration_hours: number | null; perks: string[];
  badge: string | null; position: number; active: boolean; free_eligible: boolean };

/** Plan editor; confirms price/duration changes and hiding. */
export function PlanCard({ plan, action, freeOn, stats, priceLabel, durationHint }: {
  plan: Plan; action: (f: FormData) => Promise<void>; freeOn: boolean;
  stats: { subscribers: number; orders: number }; priceLabel: string; durationHint: string;
}) {
  const ref = useRef<HTMLFormElement>(null);
  function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    const f = new FormData(e.currentTarget);
    const warn: string[] = [];
    if (Number(f.get('price_inr')) !== plan.price_inr) warn.push(`price ₹${plan.price_inr} → ₹${f.get('price_inr')}`);
    const oldLen = plan.duration_hours ? `${plan.duration_hours} hours` : `${plan.duration_days} days`;
    const newLen = `${f.get('duration')} ${f.get('duration_unit')}`;
    if (oldLen !== newLen) warn.push(`duration ${oldLen} → ${newLen}`);
    if (plan.active && !f.get('active')) warn.push('hide it from the app');
    if (warn.length && !window.confirm(`Change ${warn.join(', ')}? Applies to new orders only; existing subscriptions keep their end date.`)) e.preventDefault();
  }
  return (
    <form ref={ref} action={action} onSubmit={onSubmit} className={`card space-y-2 ${plan.active ? '' : 'opacity-70'}`}>
      <input type="hidden" name="id" value={plan.id} />
      <div className="flex items-center justify-between">
        <h2 className="h2 mb-0">{plan.name} <span className="text-sm font-normal text-muted">{priceLabel}</span></h2>
        <span className="font-mono text-xs text-muted" title="Code is read-only">{plan.code}</span>
      </div>
      <p className="text-xs text-muted">{stats.subscribers} active subscribers · {stats.orders} orders</p>
      <div className="grid grid-cols-2 gap-2">
        <div><label className="label" htmlFor={`name-${plan.id}`}>Name</label><input id={`name-${plan.id}`} name="name" className="input" defaultValue={plan.name} required /></div>
        <div><label className="label" htmlFor={`price-${plan.id}`}>Price ₹</label><input id={`price-${plan.id}`} name="price_inr" type="number" min={1} step={1} className="input" defaultValue={plan.price_inr} required /></div>
        <div><label className="label" htmlFor={`days-${plan.id}`}>Duration <span className="text-muted">= {durationHint}</span></label>
          <div className="flex gap-1">
            <input id={`days-${plan.id}`} name="duration" type="number" min={1} max={8784} className="input"
              defaultValue={plan.duration_hours ?? plan.duration_days} required />
            <select name="duration_unit" aria-label="Duration unit" className="input w-24" defaultValue={plan.duration_hours ? 'hours' : 'days'}>
              <option value="days">days</option><option value="hours">hours</option></select>
          </div></div>
        <div><label className="label" htmlFor={`badge-${plan.id}`}>Badge</label><input id={`badge-${plan.id}`} name="badge" className="input" defaultValue={plan.badge ?? ''} /></div>
        <div><label className="label" htmlFor={`pos-${plan.id}`}>Order</label><input id={`pos-${plan.id}`} name="position" type="number" className="input" defaultValue={plan.position} /></div>
      </div>
      <div><label className="label" htmlFor={`perks-${plan.id}`}>Perks (one per line)</label><textarea id={`perks-${plan.id}`} name="perks" rows={3} className="input" defaultValue={plan.perks.join('\n')} /></div>
      <label className="flex items-center gap-2 text-sm"><input type="checkbox" name="active" defaultChecked={plan.active} /> Show in app</label>
      <label className="flex items-center gap-2 text-sm"><input type="checkbox" name="free_eligible" defaultChecked={plan.free_eligible} /> Free when free plans are on {freeOn && plan.free_eligible && <span className="badge bg-emerald-100 text-emerald-700">FREE now</span>}</label>
      <button className="btn-primary">Save plan</button>
    </form>
  );
}
