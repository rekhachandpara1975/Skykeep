'use client';
import { useEffect } from 'react';
import Script from 'next/script';

type Fbq = ((...a: unknown[]) => void) & { callMethod?: (...a: unknown[]) => void; queue: unknown[]; loaded: boolean; version: string; push: unknown };

declare global { interface Window { fbq?: Fbq; _fbq?: Fbq } }

function initPixel(id: string) {
  if (window.fbq) return;
  const f = function (...a: unknown[]) { if (f.callMethod) f.callMethod(...a); else f.queue.push(a); } as Fbq;
  f.queue = []; f.loaded = true; f.version = '2.0'; f.push = f;
  window.fbq = window._fbq = f;
  window.fbq('init', id);
}

const cookie = (n: string) => document.cookie.split('; ').find((c) => c.startsWith(`${n}=`))?.split('=')[1] ?? null;

export function DownloadClient({ apkUrl, pixelId }: { apkUrl: string; pixelId: string | null }) {
  useEffect(() => {
    if (pixelId) { initPixel(pixelId); window.fbq?.('track', 'PageView'); window.fbq?.('track', 'ViewContent'); }
    const fbclid = new URLSearchParams(location.search).get('fbclid');
    // give the pixel a moment to set _fbp, then store the click for Meta matching
    const t = setTimeout(() => {
      fetch('/api/click', { method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ fbclid, fbp: cookie('_fbp'), fbc: cookie('_fbc'), path: location.pathname }) }).catch(() => {});
    }, 1500);
    return () => clearTimeout(t);
  }, [pixelId]);

  return (
    <>
      {pixelId && <Script src="https://connect.facebook.net/en_US/fbevents.js" strategy="afterInteractive" />}
      <a href={apkUrl} onClick={() => window.fbq?.('track', 'Lead')} download
        className="gradient mt-6 inline-block rounded-xl px-8 py-3 font-semibold text-white">Download APK</a>
    </>
  );
}
