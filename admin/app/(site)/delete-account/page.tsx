import { APP_NAME } from '@/lib/site';
import { DeletionForm } from './form';

export const metadata = { title: 'Delete your account' };

export default function DeleteAccount() {
  return (
    <main className="mx-auto max-w-3xl space-y-4 px-4 text-slate-300">
      <h1 className="text-3xl font-bold text-white">Delete your {APP_NAME} account</h1>
      <h2 className="text-xl font-semibold text-white">In the app (fastest)</h2>
      <p>Open {APP_NAME} › Profile › Settings › <b>Delete account</b> and confirm. Your account and files are removed immediately.</p>
      <h2 className="text-xl font-semibold text-white">Request by email</h2>
      <p>Can&apos;t open the app? Send this form. We reply within 7 days.</p>
      <DeletionForm />
      <h2 className="text-xl font-semibold text-white">Delete only some data</h2>
      <p>You can delete single files and folders in the Cloud tab, posts in your channel, or choose “Delete only some data” in the form and tell us what to remove.</p>
      <h2 className="text-xl font-semibold text-white">What we keep</h2>
      <p>Payment records (amount, date, reference, transaction id) are kept for 8 years for Indian tax law, without your name or files. Everything else is deleted.</p>
    </main>
  );
}
