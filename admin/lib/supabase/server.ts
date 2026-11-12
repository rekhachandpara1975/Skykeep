import { createServerClient } from '@supabase/ssr';
import { createClient as createPlain } from '@supabase/supabase-js';
import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';

const URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const KEY = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!;

/** Supabase client acting as the signed-in admin (RLS applies). */
export async function supabaseServer() {
  const store = await cookies();
  return createServerClient(URL, KEY, {
    cookies: {
      getAll: () => store.getAll(),
      setAll: (list) => {
        try { list.forEach(({ name, value, options }) => store.set(name, value, options)); } catch { /* server component */ }
      },
    },
  });
}

/** Anonymous public client for the website (no session). */
export const supabasePublic = () => createPlain(URL, KEY, { auth: { persistSession: false } });

/** Secret-key client — server only, used for inviting admins and storing ad clicks. */
export function supabaseSecret() {
  const secret = process.env.SUPABASE_SECRET_KEY;
  if (!secret) throw new Error('SUPABASE_SECRET_KEY is not set in Vercel');
  return createPlain(URL, secret, { auth: { persistSession: false } });
}

export type AdminCtx = { userId: string; email: string; role: 'owner' | 'content' };

export async function requireAdmin(ownerOnly = false): Promise<AdminCtx> {
  const sb = await supabaseServer();
  const { data: { user } } = await sb.auth.getUser();
  if (!user || user.is_anonymous) redirect('/control-7x2k/login');
  const { data: row } = await sb.from('admins').select('role').eq('user_id', user.id).maybeSingle();
  if (!row) redirect('/control-7x2k/login?error=not_admin');
  if (ownerOnly && row.role !== 'owner') redirect('/control-7x2k');
  return { userId: user.id, email: user.email ?? '', role: row.role };
}
