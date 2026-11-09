import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';

type Result = { error?: { message: string } | null } | void;

/** Runs a mutation, then redirects back with a flash message. */
export async function run(path: string, ok: string, fn: () => Promise<Result>) {
  let err: string | null = null;
  try {
    const r = await fn();
    if (r && r.error) err = r.error.message;
  } catch (e) {
    err = e instanceof Error ? e.message : 'Something went wrong';
  }
  revalidatePath(path);
  const sep = path.includes('?') ? '&' : '?';
  redirect(`${path}${sep}${err ? 'err' : 'msg'}=${encodeURIComponent(err ?? ok)}`);
}

export const str = (f: FormData, k: string) => String(f.get(k) ?? '').trim();
export const num = (f: FormData, k: string) => Number(f.get(k) ?? 0);
export const bool = (f: FormData, k: string) => f.get(k) === 'on' || f.get(k) === 'true';
