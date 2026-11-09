import { APP_NAME, SUPPORT_EMAIL } from '@/lib/site';

export const metadata = { title: 'Privacy policy' };

export default function Privacy() {
  return (
    <main className="prose-invert mx-auto max-w-3xl space-y-4 px-4 text-slate-300 [&_h1]:text-3xl [&_h1]:font-bold [&_h1]:text-white [&_h2]:mt-6 [&_h2]:text-xl [&_h2]:font-semibold [&_h2]:text-white">
      <h1>Privacy policy</h1>
      <p>Last updated: 9 November 2026. This policy explains what {APP_NAME} collects and why.</p>
      <h2>What we collect</h2>
      <ul className="list-disc pl-6">
        <li>Account: email address, display name, avatar (if you add one). Guests get an anonymous id.</li>
        <li>Your files: stored privately; only you can open them through short-lived signed links.</li>
        <li>Install source: whether the app was installed from an ad link or not (from the install referrer), used to show the right content and plans.</li>
        <li>Payments: plan, amount, UPI reference and transaction id returned by your UPI app. We never see your bank account, card or UPI PIN.</li>
        <li>Reports you send and content you post in channels.</li>
      </ul>
      <h2>How we use it</h2>
      <p>To run the service, activate plans, prevent fraud, moderate content and answer support. If you came from a Meta ad, we send Meta hashed identifiers (never your files) to measure installs and purchases.</p>
      <h2>Sharing</h2>
      <p>We use Supabase (database and storage) and Vercel (website hosting). We do not sell your data. The app contains no advertising SDKs.</p>
      <h2>Retention</h2>
      <p>You can delete your account at any time. Payment records are kept for 8 years as required by Indian tax law, without your files.</p>
      <h2>Your rights</h2>
      <p>Ask for a copy, correction or deletion of your data at <a className="underline" href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a>.</p>
    </main>
  );
}
