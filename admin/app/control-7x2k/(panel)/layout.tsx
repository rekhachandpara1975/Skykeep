import { Suspense } from 'react';
import type { Metadata } from 'next';
import { requireAdmin, supabaseServer } from '@/lib/supabase/server';
import { Flash } from '@/components/ui';
import { Nav } from './nav';
import { SHORT_CODE, APP_NAME } from '@/lib/site';

export const metadata: Metadata = { robots: { index: false, follow: false } };
export const dynamic = 'force-dynamic';

export default async function PanelLayout({ children }: { children: React.ReactNode }) {
  const me = await requireAdmin();
  const sb = await supabaseServer();
  const { data: s } = await sb.rpc('admin_stats');
  const counts: Record<string, number> = s ? {
    '/control-7x2k/channels': s.channel_requests, '/control-7x2k/approvals': s.organic_waiting,
    '/control-7x2k/payments': s.review_orders + s.verify_today, '/control-7x2k/requests': s.open_requests,
  } : {};

  return (
    <div className="md:flex">
      <aside className="border-b border-line bg-white md:sticky md:top-0 md:h-screen md:w-56 md:shrink-0 md:border-b-0 md:border-r">
        <div className="flex items-center gap-2 p-4">
          <span className="grid h-8 w-8 place-items-center rounded-lg bg-accent text-sm font-bold text-white">{SHORT_CODE}</span>
          <span className="font-semibold">{APP_NAME}</span>
          <span className="ml-auto text-xs text-muted md:hidden">{me.role}</span>
        </div>
        <Nav role={me.role} counts={counts} />
        <form action="/control-7x2k/logout" method="post" className="hidden p-4 md:block">
          <p className="mb-2 truncate text-xs text-muted">{me.email} · {me.role}</p>
          <button className="btn-ghost w-full">Log out</button>
        </form>
      </aside>
      <main className="min-w-0 flex-1 p-4 md:p-6">
        <Suspense><Flash /></Suspense>
        {children}
      </main>
    </div>
  );
}
