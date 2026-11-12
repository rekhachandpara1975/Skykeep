'use server';
import { requireAdmin, supabaseServer } from '@/lib/supabase/server';
import { run, str } from '@/lib/action';

export async function reviewChannel(f: FormData) {
  await requireAdmin(true);
  const approve = str(f, 'decision') === 'approve';
  await run('/control-7x2k/channels', approve ? 'Channel approved' : 'Channel rejected', async () => {
    const sb = await supabaseServer();
    return sb.rpc('admin_review_channel', { p_channel_id: str(f, 'id'), p_approve: approve, p_audience: str(f, 'audience') || 'all' });
  });
}

export async function saveChannel(f: FormData) {
  await requireAdmin();
  const id = str(f, 'id');
  const row = {
    name: str(f, 'name'),
    description: str(f, 'description') || null,
    category: str(f, 'category') || null,
    tags: str(f, 'tags').split(',').map((t) => t.trim()).filter(Boolean),
    audience: str(f, 'audience') || 'all',
    status: str(f, 'status') || 'published',
    icon_url: str(f, 'icon_url') || null,
  };
  await run('/control-7x2k/channels', id ? 'Channel saved' : 'Channel created', async () => {
    const sb = await supabaseServer();
    return id ? sb.from('channels').update(row).eq('id', id) : sb.from('channels').insert(row);
  });
}

export async function toggleHidden(f: FormData) {
  await requireAdmin();
  await run('/control-7x2k/channels', 'Channel updated', async () => {
    const sb = await supabaseServer();
    return sb.from('channels').update({ hidden: str(f, 'hidden') === 'true' }).eq('id', str(f, 'id'));
  });
}

export async function deleteChannel(f: FormData) {
  await requireAdmin(true);
  await run('/control-7x2k/channels', 'Channel deleted', async () => {
    const sb = await supabaseServer();
    return sb.from('channels').delete().eq('id', str(f, 'id'));
  });
}
