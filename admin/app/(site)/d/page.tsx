import { supabasePublic } from '@/lib/supabase/server';
import { APP_NAME, ADS_APK_PATH } from '@/lib/site';
import { DownloadClient } from './client';

export const metadata = { title: `Download ${APP_NAME} for Android` };
export const revalidate = 300;

export default async function Download() {
  const sb = supabasePublic();
  const { data: m } = await sb.from('meta_settings').select('pixel_id, enabled').single();
  const apk = sb.storage.from('downloads').getPublicUrl(ADS_APK_PATH).data.publicUrl;
  return (
    <main className="mx-auto max-w-xl px-4 py-10 text-center">
      <h1 className="text-3xl font-bold">Get {APP_NAME}</h1>
      <p className="mt-2 text-slate-300">15 GB free cloud storage and creator channels. Android 7.0 or newer.</p>
      <DownloadClient apkUrl={apk} pixelId={m?.enabled ? m.pixel_id : null} />
      <ol className="mx-auto mt-8 max-w-sm list-decimal space-y-1 text-left text-sm text-slate-300">
        <li>Tap Download and open the file when it finishes.</li>
        <li>If Android asks, allow installing from this browser.</li>
        <li>Open {APP_NAME} — no sign-up needed to start.</li>
      </ol>
    </main>
  );
}
