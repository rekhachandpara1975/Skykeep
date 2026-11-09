'use client';
import { useFormStatus } from 'react-dom';
import { useSearchParams } from 'next/navigation';

/** Flash message from ?msg= / ?err= after every save. */
export function Flash() {
  const q = useSearchParams();
  const msg = q.get('msg');
  const err = q.get('err');
  if (!msg && !err) return null;
  return (
    <div role={err ? 'alert' : 'status'} className={`mb-4 rounded-lg px-3 py-2 text-sm ${err ? 'error-alert bg-red-50 text-red-700' : 'bg-emerald-50 text-emerald-700'}`}>
      {err ?? msg}
    </div>
  );
}

/** Submit button that asks for confirmation (every destructive action confirms). */
export function Submit({ children, confirm, className = 'btn-primary', name, value }: {
  children: React.ReactNode; confirm?: string; className?: string; name?: string; value?: string;
}) {
  const { pending } = useFormStatus();
  return (
    <button type="submit" name={name} value={value} disabled={pending} className={className}
      onClick={(e) => { if (confirm && !window.confirm(confirm)) e.preventDefault(); }}>
      {pending ? '…' : children}
    </button>
  );
}
