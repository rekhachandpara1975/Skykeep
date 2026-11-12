import { APP_NAME, SUPPORT_EMAIL } from '@/lib/site';

export const metadata = { title: 'Privacy policy' };

export default function Privacy() {
  return (
    <main className="prose-invert mx-auto max-w-3xl space-y-4 px-4 text-slate-300 [&_h1]:text-3xl [&_h1]:font-bold [&_h1]:text-white [&_h2]:mt-6 [&_h2]:text-xl [&_h2]:font-semibold [&_h2]:text-white">
      <h1>Privacy policy</h1>
      <p>Last updated: 12 November 2026. This policy explains what {APP_NAME} collects, why, and the choices you have.</p>
      <h2>What we collect</h2>
      <ul className="list-disc pl-6">
        <li>Account: an anonymous user id when you start as a guest; your email address and password if you create an account; a display name and avatar if you add them.</li>
        <li>Your files: photos, videos and documents you upload. They are stored privately and only you can open them, through short-lived signed links.</li>
        <li>Channels: channels you create or join, posts you publish, and reports you send.</li>
        <li>Payments: plan, amount, order reference, and the UPI transaction id or UTR returned by your UPI app or typed by you, plus a payment screenshot only if you choose to upload one. We never see your bank account, card or UPI PIN.</li>
        <li>Device check (Google Play version): a Google Play Integrity result confirming the app is genuine and installed from Play, used to give 15 GB of free storage and prevent abuse. We do not collect your phone number, contacts or location.</li>
        <li>Install source: a random install id and whether the app was installed from one of our ad links, used to show the right content and plans.</li>
      </ul>
      <h2>How we use it</h2>
      <p>To run the service, store your files, activate plans, prevent fraud, moderate content and answer support. If you installed {APP_NAME} from one of our Meta (Facebook/Instagram) ads, we may send Meta a hashed email address and hashed user id (never your files) to measure installs, sign-ups and purchases. Users who did not come from such an ad, including everyone who installs from Google Play, are never reported to Meta.</p>
      <h2>Sharing</h2>
      <p>Supabase (database and file storage) and Vercel (website hosting) process data only on our behalf. We do not sell your data. The app contains no advertising, analytics or crash-reporting SDKs.</p>
      <h2>Notifications</h2>
      <p>The app may ask for permission to send notifications. You can turn them off at any time in your phone&apos;s settings.</p>
      <h2>Security</h2>
      <p>All connections use HTTPS. Files are private by default and access rules are enforced on our servers. No system is perfectly secure, so keep a copy of important files.</p>
      <h2>Retention and deletion</h2>
      <p>You can delete your account in the app (profile icon › Settings › Delete Account) or at <a className="underline" href="/delete-account">/delete-account</a>. Your account, files, channels and posts are deleted. Payment records (amount, date, reference, transaction id) are kept for 8 years as required by Indian tax law, without your name or files.</p>
      <h2>Children</h2>
      <p>{APP_NAME} is for people aged 18 and over. We do not knowingly collect data from children; if you believe a child has an account, contact us and we will delete it.</p>
      <h2>Your rights</h2>
      <p>Ask for a copy, correction or deletion of your data at <a className="underline" href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a>.</p>
      <h2>Changes</h2>
      <p>We will update this page and the date at the top when this policy changes, and tell you in the app about important changes.</p>
    </main>
  );
}
