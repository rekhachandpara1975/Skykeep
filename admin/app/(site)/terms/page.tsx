import { APP_NAME, SUPPORT_EMAIL } from '@/lib/site';

export const metadata = { title: 'Terms, refunds & community rules' };

export default function Terms() {
  return (
    <main className="mx-auto max-w-3xl space-y-4 px-4 text-slate-300 [&_h1]:text-3xl [&_h1]:font-bold [&_h1]:text-white [&_h2]:mt-6 [&_h2]:text-xl [&_h2]:font-semibold [&_h2]:text-white">
      <h1>Terms of service</h1>
      <p>By using {APP_NAME} you agree to these terms. Last updated: 9 November 2026.</p>
      <h2>Accounts</h2>
      <p>You must be 18 or older to post content or buy a plan. Keep your password safe; you are responsible for activity on your account.</p>
      <h2>Plans and payments</h2>
      <p>Plans are paid in Indian rupees through UPI. A plan starts when your payment is confirmed and runs for the duration shown at purchase. Plans do not renew automatically. A new purchase is added after your current end date.</p>
      <h2 id="refunds">Refunds</h2>
      <p>If money left your account but the plan did not activate within 24 hours, email {SUPPORT_EMAIL} with the reference shown in the app and we will activate it or refund in full within 7 working days. Other refunds are given if you ask within 48 hours of purchase and have not used more than 15 GB of storage.</p>
      <h2 id="community">Community rules</h2>
      <ul className="list-disc pl-6">
        <li>No sexual or nude content, no content involving minors — ever.</li>
        <li>No violence, hate, harassment, scams or spam.</li>
        <li>Only upload content you own or have the rights to.</li>
        <li>We review new channels and may hide content or close accounts that break these rules.</li>
      </ul>
      <h2 id="copyright">Copyright</h2>
      <p>To report copyright infringement, use the report button in the app or the report-content page, with proof of ownership. We remove infringing content and close repeat-infringer accounts.</p>
      <h2>Liability</h2>
      <p>Keep a copy of important files. Our liability is limited to the amount you paid in the last 12 months.</p>
      <p>Contact: <a className="underline" href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a></p>
    </main>
  );
}
