import Link from 'next/link';
import type { Metadata } from 'next';
import { supabasePublic } from '@/lib/supabase/server';
import { APP_NAME } from '@/lib/site';

type P = { params: Promise<{ id: string }> };
const UUID = /^[0-9a-f-]{36}$/i;

async function load(id: string) {
  if (!UUID.test(id)) return null;
  // public client: RLS only returns published, all-audience posts
  const { data } = await supabasePublic().from('posts').select('id,title,description,channels(name)').eq('id', id).maybeSingle();
  return data as { id: string; title: string; description: string | null; channels: { name: string } | null } | null;
}

export async function generateMetadata({ params }: P): Promise<Metadata> {
  const p = await load((await params).id);
  return { title: p?.title ?? `Shared on ${APP_NAME}`, description: p?.description ?? `Open this post in ${APP_NAME}.` };
}

export default async function SharedPost({ params }: P) {
  const { id } = await params;
  const p = await load(id);
  return (
    <main className="mx-auto max-w-xl px-4 py-10 text-center">
      <p className="text-sm text-slate-400">{p?.channels?.name ?? APP_NAME}</p>
      <h1 className="mt-1 text-3xl font-bold">{p?.title ?? 'Open this post in the app'}</h1>
      {p?.description && <p className="mt-3 text-slate-300">{p.description}</p>}
      <p className="mt-6 text-sm text-slate-400">Watch it in the {APP_NAME} app.</p>
      <Link href="/d" className="gradient mt-3 inline-block rounded-xl px-6 py-3 font-semibold text-white">Get {APP_NAME}</Link>
    </main>
  );
}
