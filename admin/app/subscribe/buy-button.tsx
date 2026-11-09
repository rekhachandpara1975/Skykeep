'use client';
import { useState } from 'react';
import { JS_CHANNEL } from '@/lib/site';

type Channel = { postMessage: (m: string) => void };

/** Sends {type:"buy", plan_id} to the app through the WebView JavaScript channel. */
export function BuyButton({ planId, label, disabled, price }: { planId: string; label: string; disabled?: boolean; price: number }) {
  const [noApp, setNoApp] = useState(false);
  function buy() {
    const ch = (window as unknown as Record<string, Channel | undefined>)[JS_CHANNEL];
    if (!ch) { setNoApp(true); return; }
    ch.postMessage(JSON.stringify({ type: 'buy', plan_id: planId, price_inr: price }));
  }
  return (
    <>
      <button onClick={buy} disabled={disabled}
        className="gradient mt-3 w-full rounded-xl py-3 font-semibold text-white disabled:opacity-40">{label}</button>
      {noApp && <p className="mt-2 text-center text-xs text-slate-400">Open this page in the app to continue.</p>}
    </>
  );
}
