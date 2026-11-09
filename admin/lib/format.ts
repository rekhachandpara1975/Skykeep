const inr = new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 2 });
const inrWhole = new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 0 });
const dt = new Intl.DateTimeFormat('en-IN', { timeZone: 'Asia/Kolkata', dateStyle: 'medium', timeStyle: 'short' });
const d = new Intl.DateTimeFormat('en-IN', { timeZone: 'Asia/Kolkata', dateStyle: 'medium' });

/** ₹ with Indian grouping (₹1,23,456). */
export const rupees = (v: number | null | undefined, whole = true) => (whole ? inrWhole : inr).format(Number(v ?? 0));
export const paise = (p: number | null | undefined) => inr.format(Number(p ?? 0) / 100);
export const count = (v: number | null | undefined) => new Intl.NumberFormat('en-IN').format(Number(v ?? 0));

/** Dates always shown in IST. */
export const dateTime = (s: string | null | undefined) => (s ? `${dt.format(new Date(s))} IST` : '—');
export const date = (s: string | null | undefined) => (s ? d.format(new Date(s)) : '—');

export function bytes(n: number | null | undefined) {
  let v = Number(n ?? 0);
  const u = ['B', 'KB', 'MB', 'GB', 'TB'];
  let i = 0;
  while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
  return `${v.toFixed(i ? 1 : 0)} ${u[i]}`;
}

export function durationLabel(days: number) {
  if (days % 365 === 0) return `= ${days / 365} year${days === 365 ? '' : 's'}`;
  if (days % 30 === 0) return `= ${days / 30} month${days === 30 ? '' : 's'}`;
  if (days % 7 === 0) return `= ${days / 7} week${days === 7 ? '' : 's'}`;
  return `= ${days} days`;
}
