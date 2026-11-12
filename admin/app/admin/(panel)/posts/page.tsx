import Link from 'next/link';
import { requireAdmin, supabaseServer } from '@/lib/supabase/server';
import { dateTime } from '@/lib/format';
import { PostEditor } from './editor';

type SP = { channel?: string; status?: string; audience?: string; edit?: string };

export default async function Posts({ searchParams }: { searchParams: Promise<SP> }) {
  const me = await requireAdmin();
  const sp = await searchParams;
  const sb = await supabaseServer();

  let cq = sb.from('channels').select('id,name').order('name');
  if (me.role === 'content') {
    const { data: acc } = await sb.from('admin_channel_access').select('channel_id').eq('user_id', me.userId);
    cq = cq.in('id', (acc ?? []).map((a) => a.channel_id));
  }
  const { data: channels = [] } = await cq;
  const ids = (channels ?? []).map((c) => c.id);

  let q = sb.from('posts').select('id,title,status,audience,publish_at,hidden,created_at,channel_id,post_items(count)')
    .order('created_at', { ascending: false }).limit(300);
  if (sp.channel) q = q.eq('channel_id', sp.channel); else if (me.role === 'content') q = q.in('channel_id', ids);
  if (sp.status) q = q.eq('status', sp.status);
  if (sp.audience) q = q.eq('audience', sp.audience);
  const { data: posts = [] } = await q;
  const name = new Map((channels ?? []).map((c) => [c.id, c.name]));

  let editing = null;
  if (sp.edit && sp.edit !== 'new') {
    const { data } = await sb.from('posts').select('*, post_items(*)').eq('id', sp.edit).maybeSingle();
    editing = data;
  }

  return (
    <>
      <div className="mb-4 flex items-center justify-between">
        <h1 className="h1 mb-0">Posts</h1>
        {!!channels?.length && <Link href={`/admin/posts?edit=new${sp.channel ? `&channel=${sp.channel}` : ''}`} className="btn-primary">New post</Link>}
      </div>

      {(sp.edit === 'new' || editing) && (
        <PostEditor key={sp.edit} channels={channels ?? []} post={editing} defaultChannel={sp.channel} />
      )}

      <form className="card mb-4 flex flex-wrap items-end gap-2">
        <div><label className="label" htmlFor="f-ch">Channel</label>
          <select id="f-ch" name="channel" className="input" defaultValue={sp.channel ?? ''}><option value="">All</option>{channels?.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}</select></div>
        <div><label className="label" htmlFor="f-st">Status</label>
          <select id="f-st" name="status" className="input" defaultValue={sp.status ?? ''}><option value="">All</option>{['draft', 'published', 'scheduled'].map((s) => <option key={s}>{s}</option>)}</select></div>
        <div><label className="label" htmlFor="f-au">Audience</label>
          <select id="f-au" name="audience" className="input" defaultValue={sp.audience ?? ''}><option value="">All</option>{['all', 'organic', 'ads'].map((s) => <option key={s}>{s}</option>)}</select></div>
        <button className="btn-ghost">Filter</button>
      </form>

      <div className="card overflow-x-auto">
        <table className="table">
          <thead><tr><th>Title</th><th>Channel</th><th>Status</th><th>Audience</th><th>Items</th><th>Created</th><th /></tr></thead>
          <tbody>
            {(posts ?? []).map((p) => (
              <tr key={p.id} className={p.hidden ? 'opacity-50' : ''}>
                <td className="font-medium">{p.title}</td><td>{name.get(p.channel_id) ?? '—'}</td>
                <td>{p.status}{p.status === 'scheduled' && <span className="block text-xs text-muted">{dateTime(p.publish_at)}</span>}</td>
                <td>{p.audience}</td><td>{(p.post_items as unknown as { count: number }[])?.[0]?.count ?? 0}</td>
                <td className="whitespace-nowrap text-xs">{dateTime(p.created_at)}</td>
                <td><Link className="btn-ghost" href={`/admin/posts?edit=${p.id}${sp.channel ? `&channel=${sp.channel}` : ''}`}>Edit</Link></td>
              </tr>
            ))}
            {!posts?.length && <tr><td colSpan={7} className="text-muted">No posts.</td></tr>}
          </tbody>
        </table>
      </div>
    </>
  );
}
