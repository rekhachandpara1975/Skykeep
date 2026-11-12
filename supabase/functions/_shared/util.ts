import { createClient, SupabaseClient, User } from 'npm:@supabase/supabase-js@2.45.4';

export const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-signature',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

export const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

export const admin = (): SupabaseClient =>
  createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false },
  });

/** Client acting as the caller (RLS applies) + the verified user. */
export async function caller(req: Request): Promise<{ db: SupabaseClient; user: User } | null> {
  const auth = req.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ')) return null;
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false },
  });
  const { data, error } = await db.auth.getUser(auth.slice(7));
  if (error || !data.user) return null;
  return { db, user: data.user };
}

export async function isOwner(uid: string): Promise<boolean> {
  const { data } = await admin().from('admins').select('role').eq('user_id', uid).maybeSingle();
  return data?.role === 'owner';
}

export function serve(handler: (req: Request) => Promise<Response>) {
  Deno.serve(async (req) => {
    if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
    if (req.method !== 'POST') return json({ error: 'method not allowed' }, 405);
    try {
      return await handler(req);
    } catch (e) {
      console.error(e);
      return json({ error: e instanceof Error ? e.message : 'error' }, 400);
    }
  });
}

export async function removeUserFiles(uid: string) {
  const sb = admin();
  for (const bucket of ['cloud', 'avatars']) {
    const { data } = await sb.storage.from(bucket).list(uid, { limit: 1000 });
    if (data?.length) await sb.storage.from(bucket).remove(data.map((f) => `${uid}/${f.name}`));
  }
  // cloud files may live in nested keys; use the table as the source of truth
  const { data: files } = await sb.from('cloud_files').select('storage_key').eq('user_id', uid);
  if (files?.length) await sb.storage.from('cloud').remove(files.map((f) => f.storage_key));
}

export async function hmacHex(secret: string, body: string) {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(body));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

export function safeEqual(a: string, b: string) {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}

export async function sha256(s: string) {
  const d = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s.trim().toLowerCase()));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, '0')).join('');
}
