'use client';
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabaseBrowser } from '@/lib/supabase/client';
import { SHORT_CODE, APP_NAME } from '@/lib/site';

export default function Login() {
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [info, setInfo] = useState<string | null>(null);

  async function forgot() {
    if (!email.includes('@')) { setErr('Type your email above first, then tap "Forgot password?".'); return; }
    setBusy(true); setErr(null); setInfo(null);
    const { error } = await supabaseBrowser().auth.resetPasswordForEmail(email, { redirectTo: `${window.location.origin}/control-7x2k/reset` });
    setBusy(false);
    if (error) setErr(error.message);
    else setInfo('Password reset link sent. Open it in this browser to set a new password.');
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true); setErr(null);
    const sb = supabaseBrowser();
    const { data, error } = await sb.auth.signInWithPassword({ email, password });
    if (error || !data.user) { setErr(error?.message ?? 'Login failed'); setBusy(false); return; }
    const { data: row } = await sb.from('admins').select('role').eq('user_id', data.user.id).maybeSingle();
    if (!row) { await sb.auth.signOut(); setErr('This account is not an admin.'); setBusy(false); return; }
    router.replace('/control-7x2k');
    router.refresh();
  }

  return (
    <main className="flex min-h-screen items-center justify-center p-4">
      <form onSubmit={submit} className="card w-full max-w-sm space-y-3">
        <div className="mb-2 flex items-center gap-2">
          <span className="grid h-9 w-9 place-items-center rounded-lg bg-accent font-bold text-white">{SHORT_CODE}</span>
          <span className="text-lg font-semibold">{APP_NAME} admin</span>
        </div>
        {info && <p role="status" className="rounded bg-emerald-50 px-3 py-2 text-sm text-emerald-700">{info}</p>}
        {err && <p role="alert" className="error-alert rounded bg-red-50 px-3 py-2 text-sm text-red-700">{err}</p>}
        <div><label className="label" htmlFor="email">Email</label>
          <input id="email" className="input" type="email" autoComplete="username" required value={email} onChange={(e) => setEmail(e.target.value)} /></div>
        <div><label className="label" htmlFor="password">Password</label>
          <input id="password" className="input" type="password" autoComplete="current-password" required value={password} onChange={(e) => setPassword(e.target.value)} /></div>
        <button className="btn-primary w-full" disabled={busy}>{busy ? 'Please wait…' : 'Sign in'}</button>
        <button type="button" onClick={forgot} disabled={busy} className="w-full text-sm text-accent underline">Forgot password?</button>
        <p className="text-xs text-muted">Admins only. Ask the owner for an invite.</p>
      </form>
    </main>
  );
}
