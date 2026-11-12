'use server';
import { requireAdmin, supabaseServer } from '@/lib/supabase/server';
import { run, str } from '@/lib/action';

const back = (f: FormData) => `/admin/payments${str(f, 'f') ? `?f=${str(f, 'f')}` : ''}`;

export async function saveUpi(f: FormData) {
  await requireAdmin(true);
  await run('/admin/payments', 'UPI settings saved', async () => {
    const sb = await supabaseServer();
    return sb.from('payment_settings').update({ upi_id: str(f, 'upi_id'), payee_name: str(f, 'payee_name') }).eq('id', true);
  });
}

export async function clearUpi() {
  await requireAdmin(true);
  await run('/admin/payments', 'UPI ID cleared — payments are off', async () => {
    const sb = await supabaseServer();
    return sb.from('payment_settings').update({ upi_id: '' }).eq('id', true);
  });
}

export async function savePaymentMode(f: FormData) {
  await requireAdmin(true);
  await run('/admin/payments', 'Saved', async () => {
    const sb = await supabaseServer();
    const r = await sb.from('payment_settings').update({ enabled: str(f, 'enabled') === 'on' }).eq('id', true);
    if (r.error) return r;
    return sb.rpc('admin_set_activation_mode', { p_mode: str(f, 'instant') === 'on' ? 'instant' : 'manual' });
  });
}

export async function orderAction(f: FormData) {
  await requireAdmin(true);
  const id = str(f, 'id');
  const op = str(f, 'op');
  const calls: Record<string, [string, Record<string, unknown>, string]> = {
    mark_paid: ['admin_mark_paid', { p_order_id: id, p_utr: str(f, 'utr') }, 'Marked paid'],
    approve: ['admin_approve_review', { p_order_id: id }, 'Payment approved'],
    bank: ['admin_confirm_bank', { p_order_id: id }, 'Bank verified'],
    reject: ['admin_reject_order', { p_order_id: id, p_note: str(f, 'note') || null }, 'Order rejected'],
    revoke: ['admin_revoke_order', { p_order_id: id, p_note: str(f, 'note') || null }, 'Order revoked, plan ended'],
  };
  const c = calls[op];
  if (!c) return;
  await run(back(f), c[2], async () => (await supabaseServer()).rpc(c[0], c[1]));
}
