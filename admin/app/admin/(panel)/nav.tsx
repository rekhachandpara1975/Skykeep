'use client';
import Link from 'next/link';
import { usePathname } from 'next/navigation';

const ITEMS = [
  { href: '/admin', label: 'Dashboard', content: true },
  { href: '/admin/channels', label: 'Channels', content: true },
  { href: '/admin/posts', label: 'Posts', content: true },
  { href: '/admin/approvals', label: 'Approvals' },
  { href: '/admin/payments', label: 'Payments' },
  { href: '/admin/users', label: 'Users' },
  { href: '/admin/requests', label: 'Requests' },
  { href: '/admin/plans', label: 'Plans' },
  { href: '/admin/meta', label: 'Meta Pixel' },
  { href: '/admin/admins', label: 'Admins' },
];

export function Nav({ role, counts }: { role: 'owner' | 'content'; counts: Record<string, number> }) {
  const path = usePathname();
  return (
    <nav className="flex gap-1 overflow-x-auto px-2 pb-2 md:flex-col md:overflow-visible">
      {ITEMS.filter((i) => role === 'owner' || i.content).map((i) => {
        const active = i.href === '/admin' ? path === '/admin' : path.startsWith(i.href);
        const n = counts[i.href] ?? 0;
        return (
          <Link key={i.href} href={i.href} aria-current={active ? 'page' : undefined}
            className={`flex shrink-0 items-center justify-between gap-2 rounded-lg px-3 py-2 text-sm ${active ? 'bg-accent/10 font-medium text-accent' : 'text-slate-700 hover:bg-slate-100'}`}>
            {i.label}
            {n > 0 && <span className="rounded-full bg-red-600 px-1.5 text-xs font-semibold text-white" aria-label={`${n} waiting`}>{n}</span>}
          </Link>
        );
      })}
      <form action="/admin/logout" method="post" className="md:hidden"><button className="shrink-0 rounded-lg px-3 py-2 text-sm text-slate-700">Log out</button></form>
    </nav>
  );
}
