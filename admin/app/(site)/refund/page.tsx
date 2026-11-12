import { APP_NAME, SUPPORT_EMAIL } from '@/lib/site';

export const metadata = { title: 'Refund policy' };

export default function Refund() {
  return (
    <main className="mx-auto max-w-3xl space-y-4 px-4 text-slate-300 [&_h1]:text-3xl [&_h1]:font-bold [&_h1]:text-white [&_h2]:mt-6 [&_h2]:text-xl [&_h2]:font-semibold [&_h2]:text-white">
      <h1>Refund policy</h1>
      <p>{APP_NAME} plans are paid once through UPI and never renew automatically.</p>
      <h2>Payment taken but plan not active</h2>
      <p>If money left your account but your plan did not turn on within 24 hours, email {SUPPORT_EMAIL} with the order reference shown in the app (and your UTR if you have it). We will activate the plan or refund the full amount within 7 working days.</p>
      <h2>Changed your mind</h2>
      <p>Ask within 48 hours of purchase and before using more than 15 GB of storage, and we refund the full amount to the UPI account that paid.</p>
      <h2>Not refundable</h2>
      <p>Plans that have ended, or accounts closed for breaking our terms.</p>
      <p>Contact: <a className="underline" href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a></p>
    </main>
  );
}
