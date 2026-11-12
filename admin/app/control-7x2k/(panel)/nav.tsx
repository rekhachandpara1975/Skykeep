'use client';
import Link from 'next/link';
import { usePathname } from 'next/navigation';

const ITEMS = [
  { href: '/control-7x2k', label: 'Dashboard', content: true },
  { href: '/control-7x2k/channels', label: 'Channels', content: true },
  { href: '/control-7x2k/posts', label: 'Posts', content: true },
  { href: '/control-7x2k/approvals', label: 'Approvals' },
  { href: '/control-7x2k/payments', label: 'Payments' },
  { href: '/control-7x2k/users', label: 'Users' },
  { href: '/control-7x2k/requests', label: 'Requests' },
  { href: '/control-7x2k/plans', label: 'Plans' },
  { href: '/control-7x2k/meta', label: 'Meta Pixel' },
  { href: '/control-7x2k/admins', label: 'Admins' },
];

export function Nav({ role, counts }: { role: 'owner' | 'content'; counts: Record<string, number> }) {
  const path = usePathname();
  return (
    <nav className="flex gap-1 overflow-x-auto px-2 pb-2 md:flex-col md:overflow-visible">
      {ITEMS.filter((i) => role === 'owner' || i.content).map((i) => {
        const active = i.href === '/control-7x2k' ? path === '/control-7x2k' : path.startsWith(i.href);
        const n = counts[i.href] ?? 0;
        return (
          <Link key={i.href} href={i.href} aria-current={active ? 'page' : undefined}
            className={`flex shrink-0 items-center justify-between gap-2 rounded-lg px-3 py-2 text-sm ${active ? 'bg-accent/10 font-medium text-accent' : 'text-slate-700 hover:bg-slate-100'}`}>
            {i.label}
            {n > 0 && <span className="rounded-full bg-red-600 px-1.5 text-xs font-semibold text-white" aria-label={`${n} waiting`}>{n}</span>}
          </Link>
        );
      })}
      <form action="/control-7x2k/logout" method="post" className="md:hidden"><button className="shrink-0 rounded-lg px-3 py-2 text-sm text-slate-700">Log out</button></form>
    </nav>
  );
}
