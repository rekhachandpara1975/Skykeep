// Reads a bank "credited" SMS: amount in paise + UTR (12 digits). Returns null for anything that is not a credit.
// Works with the usual Indian bank formats, e.g.
//   "Rs.69.00 credited to A/c XX1234 on 12-11-26 by UPI Ref No 412345678901. -Bandhan Bank"
//   "INR 259.00 has been credited to your account ... UPI/CR/412345678901/RAHUL ..."
//   "Your a/c no. XX1234 is credited by Rs. 899 on 12/11/2026 (UPI Ref no 412345678901)"
export type BankCredit = { amountPaise: number; utr: string | null; payer: string | null };

export function parseBankSms(text: string): BankCredit | null {
  const t = text.replace(/\s+/g, ' ').trim();
  if (!/\b(credited|credit(?:ed)? to|received|deposited|cr\b|\/cr\/)/i.test(t)) return null;
  if (/\b(debited|debit of|withdrawn|spent|sent to|paid to)\b/i.test(t) && !/\bcredited\b/i.test(t)) return null;
  if (/\b(otp|one time password)\b/i.test(t)) return null;

  const amt = t.match(/(?:rs\.?|inr|₹)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)/i);
  if (!amt) return null;
  const rupees = Number(amt[1].replace(/,/g, ''));
  if (!Number.isFinite(rupees) || rupees <= 0) return null;

  const utr =
    t.match(/(?:upi\s*ref(?:erence)?\.?\s*(?:no\.?|number)?|utr\s*(?:no\.?)?|rrn|ref\.?\s*no\.?|imps\s*ref)\s*[:\-#]?\s*(\d{12})\b/i)?.[1] ??
    t.match(/upi\/(?:cr\/)?(\d{12})\b/i)?.[1] ??
    t.match(/\b(\d{12})\b/)?.[1] ??
    null;
  const payer = t.match(/(?:from|by)\s+([A-Za-z][A-Za-z .]{2,40}?)(?:\s+(?:on|via|ref|upi|\(|-)|[.,])/i)?.[1]?.trim() ?? null;
  return { amountPaise: Math.round(rupees * 100), utr, payer };
}
