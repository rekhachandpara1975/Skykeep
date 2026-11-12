'use client';
import { useState } from 'react';
import { uploadWithProgress } from '@/lib/supabase/client';

/** Uploads a file to Storage with a progress bar and writes the storage path into a hidden input. */
export function FileUpload({ name, bucket, folder, accept, initial, label, fixedPath, upsert }: {
  name: string; bucket: string; folder: string; accept?: string; initial?: string | null; label: string;
  fixedPath?: string; upsert?: boolean;
}) {
  const [path, setPath] = useState(initial ?? '');
  const [pct, setPct] = useState<number | null>(null);
  const [err, setErr] = useState<string | null>(null);

  async function pick(e: React.ChangeEvent<HTMLInputElement>) {
    const f = e.target.files?.[0];
    if (!f) return;
    setErr(null); setPct(0);
    const ext = f.name.includes('.') ? f.name.split('.').pop() : 'bin';
    const p = fixedPath ?? `${folder}/${crypto.randomUUID()}.${ext}`;
    try { setPath(await uploadWithProgress(bucket, p, f, setPct, upsert)); }
    catch (x) { setErr((x as Error).message); }
    setPct(null);
  }

  return (
    <div>
      <label className="label">{label}</label>
      <input type="file" accept={accept} onChange={pick} className="text-sm" aria-label={label} />
      {pct !== null && <div className="mt-1 h-2 rounded bg-slate-200"><div className="h-2 rounded bg-accent" style={{ width: `${pct}%` }} /></div>}
      {path && <p className="mt-1 truncate text-xs text-muted">Stored: {path}</p>}
      {err && <p role="alert" className="error-alert text-xs text-red-700">{err}</p>}
      <input type="hidden" name={name} value={path} />
    </div>
  );
}
