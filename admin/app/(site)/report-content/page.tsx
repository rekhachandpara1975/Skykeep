import { APP_NAME, SUPPORT_EMAIL } from '@/lib/site';

export const metadata = { title: 'Report content' };

export default function ReportContent() {
  return (
    <main className="mx-auto max-w-3xl space-y-4 px-4 text-slate-300">
      <h1 className="text-3xl font-bold text-white">Report content</h1>
      <p>In the {APP_NAME} app, open the post or channel, tap <b>⋮ › Report</b> and pick a reason: Sexual/nude, Violence, Hate/harassment, Copyright, Spam/scam or Other. You can also block the channel so you never see it again.</p>
      <p>Reports reach our team straight away. Content involving minors or non-consensual imagery is removed immediately and reported to authorities.</p>
      <h2 className="text-xl font-semibold text-white">Without the app</h2>
      <p>Email <a className="underline" href={`mailto:${SUPPORT_EMAIL}?subject=Report%20content`}>{SUPPORT_EMAIL}</a> with the share link (it looks like …/p/…), the reason, and for copyright: proof you own the work and your contact details.</p>
    </main>
  );
}
