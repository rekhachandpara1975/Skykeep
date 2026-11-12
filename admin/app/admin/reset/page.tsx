'use client';
import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabaseBrowser } from '@/lib/supabase/client';
import { APP_NAME } from '@/lib/site';

/** Opened from the password-reset email: the link signs you in, then you choose a new password. */
export default function Reset() {
  const router = useRouter();
  const [ready, setReady] = useState(false);
  const [password, setPassword] = useState('');
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    const sb = supabaseBrowser();
    const code = new URLSearchParams(window.location.search).get('code');
    (async () => {
      if (code) {
        const { error } = await sb.auth.exchangeCodeForSession(code);
        if (error) { setErr('This reset link has expired or was opened in a different browser. Ask for a new one.'); return; }
      }
      const { data } = await sb.auth.getUser();
      if (data.user) setReady(true);
      else setErr('This reset link has expired. Go back to the login page and tap "Forgot password?" again.');
    })();
  }, []);

  async function save(e: React.FormEvent) {
    e.preventDefault();
    if (password.length < 8) { setErr('Use at least 8 characters.'); return; }
    setBusy(true); setErr(null);
    const { error } = await supabaseBrowser().auth.updateUser({ password });
    setBusy(false);
    if (error) { setErr(error.message); return; }
    router.replace('/admin');
    router.refresh();
  }

  return (
    <main className="flex min-h-screen items-center justify-center p-4">
      <form onSubmit={save} className="card w-full max-w-sm space-y-3">
        <h1 className="text-lg font-semibold">{APP_NAME} — set a new password</h1>
        {err && <p role="alert" className="error-alert rounded bg-red-50 px-3 py-2 text-sm text-red-700">{err}</p>}
        {ready && <>
          <div><label className="label" htmlFor="password">New password (8+ characters)</label>
            <input id="password" className="input" type="password" autoComplete="new-password" required minLength={8}
              value={password} onChange={(e) => setPassword(e.target.value)} /></div>
          <button className="btn-primary w-full" disabled={busy}>{busy ? 'Saving…' : 'Save new password'}</button>
        </>}
        {!ready && !err && <p className="text-sm text-muted">Checking your link…</p>}
        <a href="/admin/login" className="block text-sm text-muted underline">Back to login</a>
      </form>
    </main>
  );
}
