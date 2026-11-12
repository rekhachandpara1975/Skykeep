import Link from 'next/link';
import { requireAdmin, supabaseServer } from '@/lib/supabase/server';
import { Submit } from '@/components/ui';
import { FileUpload } from '@/components/file-upload';
import { count, dateTime } from '@/lib/format';
import { reviewChannel, saveChannel, toggleHidden, deleteChannel } from './actions';

type Channel = {
  id: string; name: string; description: string | null; category: string | null; tags: string[]; icon_url: string | null;
  audience: string; status: string; review_status: string; created_by: string | null; members_count: number; hidden: boolean; created_at: string;
};

const AUDIENCES = ['all', 'organic', 'ads'];

export default async function Channels({ searchParams }: { searchParams: Promise<{ edit?: string }> }) {
  const me = await requireAdmin();
  const { edit } = await searchParams;
  const sb = await supabaseServer();

  let q = sb.from('channels').select('*').order('created_at', { ascending: false }).limit(500);
  if (me.role === 'content') {
    const { data: acc } = await sb.from('admin_channel_access').select('channel_id').eq('user_id', me.userId);
    q = q.in('id', (acc ?? []).map((a) => a.channel_id));
  }
  const { data: all = [] } = await q;
  const channels = (all ?? []) as Channel[];
  const requests = me.role === 'owner' ? channels.filter((c) => c.review_status === 'pending') : [];

  // signed icon URLs + creator info for requests
  const icons = new Map<string, string>();
  const withIcons = channels.filter((c) => c.icon_url);
  if (withIcons.length) {
    const { data } = await sb.storage.from('channel-icons').createSignedUrls(withIcons.map((c) => c.icon_url!), 3600);
    data?.forEach((d, i) => d.signedUrl && icons.set(withIcons[i].id, d.signedUrl));
  }
  const creators = new Map<string, { email: string | null; source: string }>();
  for (const c of requests) {
    if (!c.created_by || creators.has(c.created_by)) continue;
    const { data: u } = await sb.rpc('admin_users', { p_search: c.created_by, p_limit: 1 });
    creators.set(c.created_by, { email: u?.[0]?.email ?? null, source: u?.[0]?.source ?? 'organic' });
  }
  const editing = edit === 'new' ? ({} as Partial<Channel>) : channels.find((c) => c.id === edit);

  return (
    <>
      <div className="mb-4 flex items-center justify-between">
        <h1 className="h1 mb-0">Channels</h1>
        {me.role === 'owner' && <Link href="/admin/channels?edit=new" className="btn-primary">New channel</Link>}
      </div>

      {editing && (
        <form action={saveChannel} className="card mb-6 grid gap-3 sm:grid-cols-2">
          <h2 className="h2 sm:col-span-2">{editing.id ? `Edit ${editing.name}` : 'New channel (approved immediately)'}</h2>
          <input type="hidden" name="id" value={editing.id ?? ''} />
          <div><label className="label" htmlFor="name">Name</label><input id="name" name="name" className="input" required minLength={2} maxLength={80} defaultValue={editing.name} /></div>
          <div><label className="label" htmlFor="category">Category</label><input id="category" name="category" className="input" defaultValue={editing.category ?? ''} /></div>
          <div className="sm:col-span-2"><label className="label" htmlFor="description">Description</label><textarea id="description" name="description" className="input" rows={3} maxLength={2000} defaultValue={editing.description ?? ''} /></div>
          <div><label className="label" htmlFor="tags">Tags (comma separated)</label><input id="tags" name="tags" className="input" defaultValue={editing.tags?.join(', ')} /></div>
          <div className="grid grid-cols-2 gap-2">
            <div><label className="label" htmlFor="audience">Audience</label>
              <select id="audience" name="audience" className="input" defaultValue={editing.audience ?? 'all'}>{AUDIENCES.map((a) => <option key={a}>{a}</option>)}</select></div>
            <div><label className="label" htmlFor="status">Status</label>
              <select id="status" name="status" className="input" defaultValue={editing.status ?? 'published'}>{['draft', 'published', 'active'].map((a) => <option key={a}>{a}</option>)}</select></div>
          </div>
          <FileUpload name="icon_url" bucket="channel-icons" folder="admin" accept="image/*" initial={editing.icon_url} label="Icon" />
          <div className="flex items-end gap-2 sm:col-span-2">
            <Submit>Save</Submit><Link href="/admin/channels" className="btn-ghost">Cancel</Link>
          </div>
        </form>
      )}

      {me.role === 'owner' && (
        <section className="mb-6">
          <h2 className="h2">Channel requests ({requests.length})</h2>
          {!requests.length && <p className="text-sm text-muted">No channel requests.</p>}
          <div className="grid gap-3 md:grid-cols-2">
            {requests.map((c) => {
              const cr = c.created_by ? creators.get(c.created_by) : undefined;
              return (
                <form key={c.id} action={reviewChannel} className="card flex gap-3">
                  <input type="hidden" name="id" value={c.id} />
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  {icons.get(c.id) ? <img src={icons.get(c.id)} alt="" className="h-14 w-14 rounded-lg object-cover" /> : <div className="h-14 w-14 rounded-lg bg-slate-100" />}
                  <div className="min-w-0 flex-1 space-y-1">
                    <p className="font-medium">{c.name} <span className={`badge ${cr?.source === 'ads' ? 'bg-violet-100 text-violet-700' : 'bg-slate-100 text-slate-700'}`}>{cr?.source ?? 'organic'}</span></p>
                    <p className="text-xs text-muted">{cr?.email ?? 'unknown creator'} · {dateTime(c.created_at)}</p>
                    {c.description && <p className="line-clamp-3 text-sm">{c.description}</p>}
                    <div className="flex flex-wrap items-center gap-2 pt-1">
                      <label className="sr-only" htmlFor={`aud-${c.id}`}>Audience</label>
                      <select id={`aud-${c.id}`} name="audience" className="input w-auto" defaultValue="all">{AUDIENCES.map((a) => <option key={a}>{a}</option>)}</select>
                      <Submit name="decision" value="approve" className="btn-success">Approve</Submit>
                      <Submit name="decision" value="reject" className="btn-danger" confirm={`Reject “${c.name}”?`}>Reject</Submit>
                    </div>
                  </div>
                </form>
              );
            })}
          </div>
        </section>
      )}

      <div className="card overflow-x-auto">
        <table className="table">
          <thead><tr><th>Channel</th><th>Audience</th><th>Status</th><th>Review</th><th className="text-right">Members</th><th /></tr></thead>
          <tbody>
            {channels.map((c) => (
              <tr key={c.id} className={c.hidden ? 'opacity-50' : ''}>
                <td><div className="flex items-center gap-2">
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  {icons.get(c.id) ? <img src={icons.get(c.id)} alt="" className="h-8 w-8 rounded object-cover" /> : <div className="h-8 w-8 rounded bg-slate-100" />}
                  <div><p className="font-medium">{c.name}</p><p className="text-xs text-muted">{c.category}</p></div></div></td>
                <td>{c.audience}</td><td>{c.status}{c.hidden && ' · hidden'}</td>
                <td><span className={`badge ${c.review_status === 'approved' ? 'bg-emerald-100 text-emerald-700' : c.review_status === 'pending' ? 'bg-amber-100 text-amber-800' : 'bg-red-100 text-red-700'}`}>{c.review_status}</span></td>
                <td className="text-right">{count(c.members_count)}</td>
                <td className="whitespace-nowrap text-right">
                  <Link href={`/admin/channels?edit=${c.id}`} className="btn-ghost">Edit</Link>{' '}
                  <Link href={`/admin/posts?channel=${c.id}`} className="btn-ghost">Posts</Link>{' '}
                  <form action={toggleHidden} className="inline"><input type="hidden" name="id" value={c.id} /><input type="hidden" name="hidden" value={String(!c.hidden)} />
                    <Submit className="btn-ghost" confirm={c.hidden ? undefined : `Hide “${c.name}” from the app?`}>{c.hidden ? 'Unhide' : 'Hide'}</Submit></form>{' '}
                  {me.role === 'owner' && <form action={deleteChannel} className="inline"><input type="hidden" name="id" value={c.id} />
                    <Submit className="btn-danger" confirm={`Delete “${c.name}” and all its posts? This cannot be undone.`}>Delete</Submit></form>}
                </td>
              </tr>
            ))}
            {!channels.length && <tr><td colSpan={6} className="text-muted">No channels yet.</td></tr>}
          </tbody>
        </table>
      </div>
    </>
  );
}
