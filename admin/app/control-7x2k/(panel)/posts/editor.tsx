'use client';
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabaseBrowser, uploadWithProgress, videoDuration, videoThumbnail } from '@/lib/supabase/client';

type Item = {
  id?: string; media_key: string; thumbnail_key: string | null; trailer_key: string | null; mime: string | null;
  is_premium: boolean; duration_s: number | null; size_bytes: number | null; position: number;
};
type Post = {
  id: string; channel_id: string; title: string; description: string | null; audience: string; status: string;
  publish_at: string | null; hidden: boolean; post_items: Item[];
};

const ext = (f: File) => (f.name.includes('.') ? f.name.split('.').pop() : 'bin');
const toLocal = (s: string | null) => (s ? new Date(new Date(s).getTime() + 330 * 60000).toISOString().slice(0, 16) : '');

export function PostEditor({ channels, post, defaultChannel }: { channels: { id: string; name: string }[]; post: Post | null; defaultChannel?: string }) {
  const router = useRouter();
  const [channelId, setChannelId] = useState(post?.channel_id ?? defaultChannel ?? channels[0]?.id);
  const [title, setTitle] = useState(post?.title ?? '');
  const [description, setDescription] = useState(post?.description ?? '');
  const [audience, setAudience] = useState(post?.audience ?? 'all');
  const [status, setStatus] = useState(post?.status ?? 'draft');
  const [publishAt, setPublishAt] = useState(toLocal(post?.publish_at ?? null));
  const [hidden, setHidden] = useState(post?.hidden ?? false);
  const [items, setItems] = useState<Item[]>([...(post?.post_items ?? [])].sort((a, b) => a.position - b.position));
  const [removed, setRemoved] = useState<Item[]>([]);
  const [progress, setProgress] = useState<string | null>(null);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const [busy, setBusy] = useState(false);

  async function addMedia(files: FileList | null) {
    if (!files || !channelId) return;
    for (const f of Array.from(files)) {
      try {
        const key = `${channelId}/${crypto.randomUUID()}.${ext(f)}`;
        await uploadWithProgress('media', key, f, (p) => setProgress(`${f.name}: ${p}%`));
        let thumb: string | null = null;
        const blob = await videoThumbnail(f);
        if (blob) { thumb = `${channelId}/${crypto.randomUUID()}.jpg`; await uploadWithProgress('media', thumb, blob, () => {}); }
        else if (f.type.startsWith('image/')) thumb = key;
        const duration = await videoDuration(f);
        setItems((xs) => [...xs, { media_key: key, thumbnail_key: thumb, trailer_key: null, mime: f.type || null,
          is_premium: false, duration_s: duration, size_bytes: f.size, position: xs.length }]);
      } catch (e) { setMsg({ ok: false, text: (e as Error).message }); }
    }
    setProgress(null);
  }

  async function addTrailer(i: number, f: File | undefined) {
    if (!f || !channelId) return;
    try {
      const key = `${channelId}/${crypto.randomUUID()}-trailer.${ext(f)}`;
      await uploadWithProgress('media', key, f, (p) => setProgress(`Trailer: ${p}%`));
      setItems((xs) => xs.map((x, j) => (j === i ? { ...x, trailer_key: key } : x)));
    } catch (e) { setMsg({ ok: false, text: (e as Error).message }); }
    setProgress(null);
  }

  const move = (i: number, d: -1 | 1) => setItems((xs) => {
    const ys = [...xs]; const j = i + d;
    if (j < 0 || j >= ys.length) return xs;
    [ys[i], ys[j]] = [ys[j], ys[i]];
    return ys;
  });

  async function save() {
    setBusy(true); setMsg(null);
    const sb = supabaseBrowser();
    const row = { channel_id: channelId, title, description: description || null, audience, status, hidden,
      publish_at: status === 'scheduled' && publishAt ? new Date(`${publishAt}:00+05:30`).toISOString() : null };
    try {
      let id = post?.id;
      if (id) { const { error } = await sb.from('posts').update(row).eq('id', id); if (error) throw error; }
      else { const { data, error } = await sb.from('posts').insert(row).select('id').single(); if (error) throw error; id = data.id; }
      for (const r of removed.filter((x) => x.id)) {
        const { error } = await sb.from('post_items').delete().eq('id', r.id!); if (error) throw error;
        await sb.storage.from('media').remove([r.media_key, r.thumbnail_key, r.trailer_key].filter(Boolean) as string[]);
      }
      const rows = items.map(({ id: itemId, ...x }, position) => ({ ...(itemId ? { id: itemId } : {}), ...x, post_id: id, position }));
      if (rows.length) { const { error } = await sb.from('post_items').upsert(rows); if (error) throw error; }
      router.replace(`/control-7x2k/posts?edit=${id}&msg=${encodeURIComponent('Post saved')}`);
      router.refresh();
    } catch (e) { setMsg({ ok: false, text: (e as Error).message }); }
    setBusy(false);
  }

  async function remove() {
    if (!post || !window.confirm(`Delete “${post.title}” and its media? This cannot be undone.`)) return;
    setBusy(true);
    const sb = supabaseBrowser();
    const { error } = await sb.functions.invoke('post-delete', { body: { post_id: post.id } });
    if (error) { setMsg({ ok: false, text: error.message }); setBusy(false); return; }
    router.replace(`/control-7x2k/posts?msg=${encodeURIComponent('Post deleted')}`);
    router.refresh();
  }

  return (
    <div className="card mb-6 space-y-3">
      <h2 className="h2">{post ? 'Edit post' : 'New post'}</h2>
      {msg && <p role={msg.ok ? 'status' : 'alert'} className={`rounded px-3 py-2 text-sm ${msg.ok ? 'bg-emerald-50 text-emerald-700' : 'error-alert bg-red-50 text-red-700'}`}>{msg.text}</p>}
      <div className="grid gap-3 sm:grid-cols-2">
        <div><label className="label" htmlFor="p-ch">Channel</label>
          <select id="p-ch" className="input" value={channelId} onChange={(e) => setChannelId(e.target.value)} disabled={!!post}>
            {channels.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}</select></div>
        <div><label className="label" htmlFor="p-title">Title</label><input id="p-title" className="input" value={title} onChange={(e) => setTitle(e.target.value)} maxLength={200} /></div>
        <div className="sm:col-span-2"><label className="label" htmlFor="p-desc">Description</label><textarea id="p-desc" className="input" rows={3} value={description} onChange={(e) => setDescription(e.target.value)} /></div>
        <div><label className="label" htmlFor="p-aud">Audience</label>
          <select id="p-aud" className="input" value={audience} onChange={(e) => setAudience(e.target.value)}>{['all', 'organic', 'ads'].map((a) => <option key={a}>{a}</option>)}</select></div>
        <div className="grid grid-cols-2 gap-2">
          <div><label className="label" htmlFor="p-st">Status</label>
            <select id="p-st" className="input" value={status} onChange={(e) => setStatus(e.target.value)}>{['draft', 'published', 'scheduled'].map((a) => <option key={a}>{a}</option>)}</select></div>
          {status === 'scheduled' && <div><label className="label" htmlFor="p-at">Publish at (IST)</label>
            <input id="p-at" type="datetime-local" className="input" value={publishAt} onChange={(e) => setPublishAt(e.target.value)} /></div>}
        </div>
        <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={hidden} onChange={(e) => setHidden(e.target.checked)} /> Hidden from app</label>
      </div>

      <div>
        <p className="label">Media ({items.length})</p>
        <ul className="space-y-2">
          {items.map((it, i) => (
            <li key={it.id ?? it.media_key} className="flex flex-wrap items-center gap-2 rounded-lg border border-line p-2 text-sm">
              <span className="w-6 text-muted">{i + 1}</span>
              <span className="min-w-0 flex-1 truncate">{it.mime ?? 'file'} · {it.media_key.split('/').pop()}{it.duration_s ? ` · ${it.duration_s}s` : ''}{it.thumbnail_key ? ' · thumb ✓' : ''}</span>
              <label className="flex items-center gap-1"><input type="checkbox" checked={it.is_premium}
                onChange={(e) => setItems((xs) => xs.map((x, j) => (j === i ? { ...x, is_premium: e.target.checked } : x)))} /> Premium</label>
              <label className="text-xs">Trailer {it.trailer_key ? '✓' : ''} <input type="file" accept="video/*" className="w-40 text-xs" aria-label="Trailer" onChange={(e) => addTrailer(i, e.target.files?.[0])} /></label>
              <button type="button" className="btn-ghost" aria-label="Move up" onClick={() => move(i, -1)}>↑</button>
              <button type="button" className="btn-ghost" aria-label="Move down" onClick={() => move(i, 1)}>↓</button>
              <button type="button" className="btn-danger" onClick={() => { if (window.confirm('Remove this item?')) { setRemoved((r) => [...r, it]); setItems((xs) => xs.filter((_, j) => j !== i)); } }}>Remove</button>
            </li>
          ))}
        </ul>
        <input type="file" multiple accept="video/*,image/*" className="mt-2 text-sm" aria-label="Add media" onChange={(e) => addMedia(e.target.files)} />
        {progress && <p className="mt-1 text-xs text-muted" aria-live="polite">Uploading {progress}</p>}
      </div>

      <div className="flex gap-2">
        <button className="btn-primary" disabled={busy || !title || !!progress} onClick={save}>{busy ? 'Saving…' : 'Save'}</button>
        <button className="btn-ghost" onClick={() => router.push('/control-7x2k/posts')}>Close</button>
        {post && <button className="btn-danger ml-auto" disabled={busy} onClick={remove}>Delete post</button>}
      </div>
    </div>
  );
}
