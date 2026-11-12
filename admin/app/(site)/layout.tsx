import Link from 'next/link';
import { APP_NAME, SHORT_CODE, SUPPORT_EMAIL } from '@/lib/site';

export default function SiteLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="min-h-screen bg-night text-slate-100">
      <header className="mx-auto flex max-w-5xl items-center gap-2 px-4 py-4">
        <Link href="/" className="flex items-center gap-2 font-semibold">
          <span className="gradient grid h-8 w-8 place-items-center rounded-lg text-sm font-bold text-white">{SHORT_CODE}</span>{APP_NAME}
        </Link>
        <nav className="ml-auto flex gap-4 text-sm text-slate-300">
          <Link href="/#plans">Plans</Link><Link href="/#faq">FAQ</Link><Link href="/d">Download</Link>
        </nav>
      </header>
      {children}
      <footer className="mx-auto mt-16 max-w-5xl border-t border-white/10 px-4 py-8 text-sm text-slate-400">
        <div className="flex flex-wrap gap-4">
          <Link href="/privacy">Privacy</Link><Link href="/terms">Terms & refunds</Link>
          <Link href="/delete-account">Delete account</Link><Link href="/report-content">Report content</Link>
          <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a>
        </div>
        <p className="mt-4">© {new Date().getFullYear()} {APP_NAME}</p>
      </footer>
    </div>
  );
}
