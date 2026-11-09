'use client';
import { useState } from 'react';
import { supabaseBrowser } from '@/lib/supabase/client';

export function DeletionForm() {
  const [state, setState] = useState<'idle' | 'busy' | 'done' | string>('idle');
  async function submit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const f = new FormData(e.currentTarget);
    setState('busy');
    const { error } = await supabaseBrowser().functions.invoke('deletion-request', {
      body: { email: f.get('email'), scope: f.get('scope'), details: f.get('details') },
    });
    setState(error ? `Could not send: ${error.message}` : 'done');
  }
  if (state === 'done') return <p role="status" className="rounded-xl bg-emerald-500/10 p-4 text-emerald-300">Request received. We will email you to confirm.</p>;
  return (
    <form onSubmit={submit} className="space-y-3 rounded-2xl border border-white/10 bg-night-2 p-4">
      <div><label htmlFor="d-email" className="mb-1 block text-sm">Account email</label>
        <input id="d-email" name="email" type="email" required className="w-full rounded-lg bg-night px-3 py-2 text-white outline-none ring-1 ring-white/10 focus:ring-accent" /></div>
      <fieldset className="space-y-1 text-sm"><legend className="mb-1">What should we delete?</legend>
        <label className="flex gap-2"><input type="radio" name="scope" value="all" defaultChecked /> Delete my account and all data</label>
        <label className="flex gap-2"><input type="radio" name="scope" value="some" /> Delete only some data</label></fieldset>
      <div><label htmlFor="d-details" className="mb-1 block text-sm">Details (optional)</label>
        <textarea id="d-details" name="details" rows={3} maxLength={3000} className="w-full rounded-lg bg-night px-3 py-2 text-white outline-none ring-1 ring-white/10 focus:ring-accent" /></div>
      {state !== 'idle' && state !== 'busy' && <p role="alert" className="error-alert text-sm text-red-400">{state}</p>}
      <button disabled={state === 'busy'} className="gradient rounded-xl px-5 py-2 font-semibold text-white">{state === 'busy' ? 'Sending…' : 'Send request'}</button>
    </form>
  );
}
