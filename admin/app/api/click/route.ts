import { NextResponse } from 'next/server';
import { supabaseSecret } from '@/lib/supabase/server';

const clip = (v: unknown, n = 300) => (typeof v === 'string' && v ? v.slice(0, n) : null);

// Stores an ad click from /d (fbclid → fbc, fbp, IP, user agent) for Meta matching.
export async function POST(req: Request) {
  const body = await req.json().catch(() => ({}));
  const fbclid = clip(body.fbclid);
  const fbc = clip(body.fbc) ?? (fbclid ? `fb.1.${Date.now()}.${fbclid}` : null);
  const ip = (req.headers.get('x-forwarded-for') ?? '').split(',')[0].trim() || null;
  try {
    const { error } = await supabaseSecret().from('ad_clicks').insert({
      fbclid, fbc, fbp: clip(body.fbp), ip, user_agent: clip(req.headers.get('user-agent'), 500), path: clip(body.path, 100),
    });
    if (error) throw error;
  } catch (e) {
    console.error('ad click not stored', e);
  }
  return NextResponse.json({ ok: true }, { headers: fbc ? { 'Set-Cookie': `_fbc=${fbc}; Path=/; Max-Age=7776000; SameSite=Lax; Secure` } : {} });
}
