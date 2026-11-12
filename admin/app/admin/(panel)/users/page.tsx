import { requireAdmin, supabaseServer } from '@/lib/supabase/server';
import { run, str, num } from '@/lib/action';
import { Submit } from '@/components/ui';
import { bytes, dateTime } from '@/lib/format';

type SP = { q?: string; source?: string; plan?: string; guest?: string };
type U = { id: string; email: string | null; display_name: string | null; is_guest: boolean; source: string; ads_access_status: string;
  plan_name: string | null; plan_ends_at: string | null; used_bytes: number; created_at: string };

async function grant(f: FormData) {
  'use server';
  await requireAdmin(true);
  await run('/admin/users', 'Premium granted', async () => (await supabaseServer()).rpc('admin_grant_premium', {
    p_user_id: str(f, 'user_id'), p_plan_id: str(f, 'plan_id') || null, p_days: num(f, 'days') }));
}
async function access(f: FormData) {
  'use server';
  await requireAdmin(true);
  await run('/admin/users', 'Access updated', async () => (await supabaseServer()).rpc('admin_set_access', {
    p_user_id: str(f, 'user_id'), p_status: str(f, 'status') }));
}

export default async function Users({ searchParams }: { searchParams: Promise<SP> }) {
  await requireAdmin(true);
  const sp = await searchParams;
  const sb = await supabaseServer();
  const [{ data: users = [], error }, { data: plans = [] }] = await Promise.all([
    sb.rpc('admin_users', { p_search: sp.q || null, p_source: sp.source || null, p_plan: sp.plan || null,
      p_guest: sp.guest ? sp.guest === 'yes' : null, p_limit: 200 }),
    sb.from('plans').select('id,name,duration_days').order('position'),
  ]);

  return (
    <>
      <h1 className="h1">Users</h1>
      <form className="card mb-4 flex flex-wrap items-end gap-2">
        <div className="min-w-48 flex-1"><label className="label" htmlFor="q">Search email, name or id</label><input id="q" name="q" className="input" defaultValue={sp.q} /></div>
        <div><label className="label" htmlFor="src">Source</label><select id="src" name="source" className="input" defaultValue={sp.source ?? ''}><option value="">All</option><option>ads</option><option>organic</option></select></div>
        <div><label className="label" htmlFor="pl">Plan</label><select id="pl" name="plan" className="input" defaultValue={sp.plan ?? ''}><option value="">All</option><option value="active">Active plan</option><option value="none">No plan</option></select></div>
        <div><label className="label" htmlFor="gu">Guest</label><select id="gu" name="guest" className="input" defaultValue={sp.guest ?? ''}><option value="">All</option><option value="yes">Guests</option><option value="no">Logged in</option></select></div>
        <button className="btn-ghost">Filter</button>
      </form>
      {error && <p className="error-alert text-red-700">{error.message}</p>}
      <div className="card overflow-x-auto">
        <table className="table">
          <thead><tr><th>User</th><th>Source</th><th>Plan</th><th>Access</th><th>Storage</th><th>Joined</th><th>Actions</th></tr></thead>
          <tbody>
            {((users ?? []) as U[]).map((u) => (
              <tr key={u.id}>
                <td><p className="font-medium">{u.is_guest ? 'Guest' : u.display_name ?? '—'}</p><p className="text-xs text-muted">{u.email ?? u.id.slice(0, 8)}</p></td>
                <td><span className={`badge ${u.source === 'ads' ? 'bg-violet-100 text-violet-700' : 'bg-slate-100 text-slate-700'}`}>{u.source}</span></td>
                <td className="text-sm">{u.plan_name ? <>{u.plan_name}<span className="block text-xs text-muted">until {dateTime(u.plan_ends_at)}</span></> : '—'}</td>
                <td className="text-sm">{u.source === 'ads' ? 'full (ads)' : u.ads_access_status}</td>
                <td className="text-xs">{bytes(u.used_bytes)}</td>
                <td className="whitespace-nowrap text-xs">{dateTime(u.created_at)}</td>
                <td className="min-w-64">
                  {!u.is_guest && (
                    <form action={grant} className="mb-1 flex flex-wrap gap-1">
                      <input type="hidden" name="user_id" value={u.id} />
                      <select name="plan_id" className="input w-28" aria-label="Plan">{(plans ?? []).map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}</select>
                      <input name="days" type="number" min={1} max={3660} defaultValue={30} className="input w-20" aria-label="Days" />
                      <Submit className="btn-ghost" confirm="Grant premium to this user?">Grant</Submit>
                    </form>)}
                  {u.source === 'organic' && !u.is_guest && (
                    <form action={access} className="flex gap-1">
                      <input type="hidden" name="user_id" value={u.id} />
                      {u.ads_access_status !== 'approved'
                        ? <Submit name="status" value="approved" className="btn-success">Approve access</Submit>
                        : <Submit name="status" value="rejected" className="btn-danger" confirm="Revoke full access?">Revoke access</Submit>}
                    </form>)}
                </td>
              </tr>
            ))}
            {!users?.length && <tr><td colSpan={7} className="text-muted">No users match.</td></tr>}
          </tbody>
        </table>
      </div>
    </>
  );
}
