import Link from 'next/link';
import { requireAdmin, supabaseServer } from '@/lib/supabase/server';
import { run, str } from '@/lib/action';
import { Submit } from '@/components/ui';
import { dateTime } from '@/lib/format';

const KINDS = [['deletion', 'Account deletion'], ['report', 'Content reports'], ['in_app', 'In-app reports']] as const;

async function act(f: FormData) {
  'use server';
  await requireAdmin(true);
  const op = str(f, 'op');
  const back = `/control-7x2k/requests?kind=${str(f, 'kind')}`;
  const sb = await supabaseServer();
  if (op === 'close') return run(back, 'Request closed', async () => sb.from('support_requests').update({ status: 'closed' }).eq('id', str(f, 'id')));
  if (op === 'hide') return run(back, 'Content hidden and request closed', async () => {
    const table = str(f, 'target_type') === 'channel' ? 'channels' : 'posts';
    const r = await sb.from(table).update({ hidden: true }).eq('id', str(f, 'target_id'));
    if (r.error) return r;
    return sb.from('support_requests').update({ status: 'closed' }).eq('id', str(f, 'id'));
  });
  if (op === 'delete_account') return run(back, 'Account deleted', async () => {
    const { error } = await sb.functions.invoke('admin-delete-account', { body: { user_id: str(f, 'user_id'), request_id: str(f, 'id') } });
    return { error: error ? { message: error.message } : null };
  });
}

export default async function Requests({ searchParams }: { searchParams: Promise<{ kind?: string; closed?: string }> }) {
  await requireAdmin(true);
  const sp = await searchParams;
  const kind = KINDS.some(([k]) => k === sp.kind) ? sp.kind! : 'deletion';
  const sb = await supabaseServer();
  const { data: rows = [] } = await sb.from('support_requests').select('*').eq('kind', kind)
    .eq('status', sp.closed ? 'closed' : 'open').order('created_at', { ascending: false }).limit(200);

  return (
    <>
      <h1 className="h1">Requests</h1>
      <div className="mb-3 flex flex-wrap gap-2">
        {KINDS.map(([k, l]) => <Link key={k} href={`/control-7x2k/requests?kind=${k}`} className={k === kind ? 'btn-primary' : 'btn-ghost'}>{l}</Link>)}
        <Link href={`/control-7x2k/requests?kind=${kind}${sp.closed ? '' : '&closed=1'}`} className="btn-ghost ml-auto">{sp.closed ? 'Show open' : 'Show closed'}</Link>
      </div>
      <div className="space-y-3">
        {(rows ?? []).map((r) => (
          <form key={r.id} action={act} className="card">
            <input type="hidden" name="id" value={r.id} /><input type="hidden" name="kind" value={kind} />
            <input type="hidden" name="user_id" value={r.user_id ?? ''} />
            <input type="hidden" name="target_type" value={r.target_type ?? ''} /><input type="hidden" name="target_id" value={r.target_id ?? ''} />
            <div className="flex flex-wrap items-start justify-between gap-2">
              <div className="min-w-0">
                <p className="font-medium">{r.reason ?? (kind === 'deletion' ? 'Deletion request' : 'Report')}{r.target_type && <span className="ml-2 text-xs text-muted">{r.target_type} {r.target_id?.slice(0, 8)}</span>}</p>
                <p className="text-xs text-muted">{dateTime(r.created_at)} · {r.email ?? (r.user_id ? `user ${r.user_id.slice(0, 8)}` : 'anonymous')}</p>
                {r.details && <p className="mt-1 whitespace-pre-wrap text-sm">{r.details}</p>}
              </div>
              {r.status === 'open' && (
                <div className="flex flex-wrap gap-1">
                  {r.target_id && <Submit name="op" value="hide" className="btn-danger" confirm="Hide this content from the app?">Hide content</Submit>}
                  {kind === 'deletion' && r.user_id && <Submit name="op" value="delete_account" className="btn-danger" confirm="Permanently delete this account and its files? Payment records are kept for tax. This cannot be undone.">Delete account</Submit>}
                  <Submit name="op" value="close" className="btn-ghost">Close</Submit>
                </div>)}
            </div>
            {kind === 'deletion' && !r.user_id && r.status === 'open' && <p className="mt-2 text-xs text-muted">Web request by email — find the user in Users, then delete from the app account or reply to {r.email}.</p>}
          </form>
        ))}
        {!rows?.length && <p className="text-sm text-muted">Nothing here.</p>}
      </div>
    </>
  );
}
