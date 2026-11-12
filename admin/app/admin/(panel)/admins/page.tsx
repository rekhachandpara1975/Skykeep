import { requireAdmin, supabaseServer, supabaseSecret } from '@/lib/supabase/server';
import { run, str } from '@/lib/action';
import { Submit } from '@/components/ui';
import { dateTime } from '@/lib/format';
import { SITE_URL } from '@/lib/site';

async function invite(f: FormData) {
  'use server';
  await requireAdmin(true);
  await run('/admin/admins', 'Invite sent', async () => {
    const email = str(f, 'email').toLowerCase();
    const role = str(f, 'role') === 'owner' ? 'owner' : 'content';
    const channels = f.getAll('channels').map(String);
    const sec = supabaseSecret(); // server only
    // existing user? otherwise send an invite email
    let uid: string | undefined;
    const { data: list } = await sec.auth.admin.listUsers({ perPage: 1000 });
    uid = list?.users.find((u) => u.email?.toLowerCase() === email)?.id;
    if (!uid) {
      const { data, error } = await sec.auth.admin.inviteUserByEmail(email, { redirectTo: `${SITE_URL}/admin/login` });
      if (error) return { error };
      uid = data.user.id;
    }
    const sb = await supabaseServer(); // owner session: RLS checks is_owner
    const r = await sb.from('admins').upsert({ user_id: uid, role, email });
    if (r.error) return r;
    await sb.from('admin_channel_access').delete().eq('user_id', uid);
    if (role === 'content' && channels.length) {
      const c = await sb.from('admin_channel_access').insert(channels.map((channel_id) => ({ user_id: uid, channel_id })));
      if (c.error) return c;
    }
  });
}

async function remove(f: FormData) {
  'use server';
  const me = await requireAdmin(true);
  await run('/admin/admins', 'Admin removed', async () => {
    if (str(f, 'user_id') === me.userId) return { error: { message: 'You cannot remove yourself' } };
    return (await supabaseServer()).from('admins').delete().eq('user_id', str(f, 'user_id'));
  });
}

export default async function Admins() {
  await requireAdmin(true);
  const sb = await supabaseServer();
  const [{ data: admins = [] }, { data: access = [] }, { data: channels = [] }] = await Promise.all([
    sb.from('admins').select('*').order('created_at'),
    sb.from('admin_channel_access').select('user_id, channel_id'),
    sb.from('channels').select('id,name').order('name'),
  ]);
  const cname = new Map((channels ?? []).map((c) => [c.id, c.name]));

  return (
    <>
      <h1 className="h1">Admins</h1>
      <div className="grid gap-4 lg:grid-cols-3">
        <div className="card overflow-x-auto lg:col-span-2">
          <table className="table">
            <thead><tr><th>Email</th><th>Role</th><th>Channels</th><th>Added</th><th /></tr></thead>
            <tbody>{(admins ?? []).map((a) => (
              <tr key={a.user_id}><td>{a.email ?? a.user_id.slice(0, 8)}</td><td>{a.role}</td>
                <td className="text-xs">{a.role === 'owner' ? 'all' : (access ?? []).filter((x) => x.user_id === a.user_id).map((x) => cname.get(x.channel_id)).join(', ') || 'none'}</td>
                <td className="whitespace-nowrap text-xs">{dateTime(a.created_at)}</td>
                <td><form action={remove}><input type="hidden" name="user_id" value={a.user_id} />
                  <Submit className="btn-danger" confirm={`Remove ${a.email ?? 'this admin'}? (The last owner cannot be removed.)`}>Remove</Submit></form></td></tr>))}</tbody>
          </table>
        </div>
        <form action={invite} className="card space-y-2">
          <h2 className="h2 mb-0">Invite admin</h2>
          <div><label className="label" htmlFor="em">Email</label><input id="em" name="email" type="email" className="input" required /></div>
          <div><label className="label" htmlFor="role">Role</label><select id="role" name="role" className="input"><option value="content">Content (assigned channels only)</option><option value="owner">Owner (everything)</option></select></div>
          <fieldset><legend className="label">Channel access (content admins)</legend>
            <div className="max-h-48 space-y-1 overflow-y-auto">{(channels ?? []).map((c) => (
              <label key={c.id} className="flex items-center gap-2 text-sm"><input type="checkbox" name="channels" value={c.id} /> {c.name}</label>))}</div></fieldset>
          <Submit confirm="Send this admin invite?">Send invite</Submit>
        </form>
      </div>
    </>
  );
}
