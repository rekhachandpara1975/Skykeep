import Link from 'next/link';
import { revalidatePath } from 'next/cache';
import { requireAdmin, supabaseServer } from '@/lib/supabase/server';
import { run, str } from '@/lib/action';
import { Submit } from '@/components/ui';
import { date, dateTime } from '@/lib/format';

const TABS = ['pending', 'approved', 'rejected'] as const;

async function setAccess(f: FormData) {
  'use server';
  await requireAdmin(true);
  const tab = str(f, 'tab');
  await run(`/admin/approvals?tab=${tab}`, 'Access updated', async () => {
    const sb = await supabaseServer();
    const r = await sb.rpc('admin_set_access', { p_user_id: str(f, 'user_id'), p_status: str(f, 'status') });
    revalidatePath('/admin', 'layout');
    return r;
  });
}

export default async function Approvals({ searchParams }: { searchParams: Promise<{ tab?: string }> }) {
  await requireAdmin(true);
  const tab = (TABS as readonly string[]).includes((await searchParams).tab ?? '') ? (await searchParams).tab! : 'pending';
  const sb = await supabaseServer();
  const { data: rows = [], error } = await sb.rpc('admin_access_requests', { p_status: tab });

  return (
    <>
      <h1 className="h1">Approvals — organic full access</h1>
      <p className="mb-3 text-sm text-muted">Organic users who bought or claimed a plan (or asked in free mode) need your approval before they get full access and ads-audience content.</p>
      <div className="mb-3 flex gap-2" role="tablist">
        {TABS.map((t) => <Link key={t} role="tab" aria-selected={t === tab} href={`/admin/approvals?tab=${t}`} className={t === tab ? 'btn-primary' : 'btn-ghost'}>{t[0].toUpperCase() + t.slice(1)}</Link>)}
      </div>
      {error && <p className="error-alert text-red-700">{error.message}</p>}
      <div className="card overflow-x-auto">
        <table className="table">
          <thead><tr><th>User</th><th>Plan</th><th>Joined</th><th /></tr></thead>
          <tbody>
            {(rows ?? []).map((u: { id: string; email: string; display_name: string; plan_name: string | null; plan_ends_at: string | null; created_at: string }) => (
              <tr key={u.id}>
                <td><p className="font-medium">{u.display_name ?? '—'}</p><p className="text-xs text-muted">{u.email}</p></td>
                <td>{u.plan_name ? `${u.plan_name} until ${date(u.plan_ends_at)}` : 'No plan'}</td>
                <td className="text-xs">{dateTime(u.created_at)}</td>
                <td className="whitespace-nowrap text-right">
                  <form action={setAccess} className="inline-flex gap-2">
                    <input type="hidden" name="user_id" value={u.id} /><input type="hidden" name="tab" value={tab} />
                    {tab !== 'approved' && <Submit name="status" value="approved" className="btn-success">Approve</Submit>}
                    {tab === 'pending' && <Submit name="status" value="rejected" className="btn-danger" confirm="Reject full access for this user?">Reject</Submit>}
                    {tab === 'approved' && <Submit name="status" value="rejected" className="btn-danger" confirm="Revoke full access for this user?">Revoke</Submit>}
                  </form>
                </td>
              </tr>
            ))}
            {!rows?.length && <tr><td colSpan={4} className="text-muted">Nobody here.</td></tr>}
          </tbody>
        </table>
      </div>
    </>
  );
}
