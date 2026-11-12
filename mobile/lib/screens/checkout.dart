import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../services/api.dart';
import '../services/premium_web.dart';
import '../services/status.dart';
import '../services/upi.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'login_sheet.dart';

/// {type:"buy"} from the plans page → free claim or UPI checkout.
Future<void> startPurchase(BuildContext context, BuyMessage msg) async {
  final app = AppScope.read(context);
  if (!await requireMember(context, reason: 'Log in to continue with your plan')) return;
  if (!context.mounted) return;
  final plan = await app.findPlan(msg.planId);
  if (!context.mounted) return;
  if (plan == null) return toast(context, 'This plan is no longer available.');

  if (app.status.freePlanIds.contains(msg.planId)) {
    try {
      final r = await app.api.claimFreePlan(msg.planId);
      await app.refresh();
      if (context.mounted) toast(context, 'Plan activated until ${formatDate(DateTime.tryParse(r['ends_at'].toString())?.toLocal())}');
    } catch (e) {
      if (context.mounted) toast(context, friendlyError(e));
    }
    return;
  }
  await upiCheckout(context, plan: plan, shownPriceInr: msg.shownPriceInr ?? plan['price_inr'] as num);
}

/// UPI intent checkout. The phone's answer is only a hint: the server moves the order to verification
/// and the owner approves it — premium is never activated from the app.
/// [createOrder] defaults to the normal UPI order; the Play build passes the User Choice Billing order.
Future<void> upiCheckout(BuildContext context, {required Json plan, required num? shownPriceInr, Future<Json> Function()? createOrder}) async {
  final app = AppScope.read(context);
  Json order;
  try {
    order = await (createOrder ?? () => app.api.createOrder(plan['id'] as String))();
  } catch (e) {
    if (context.mounted) toast(context, friendlyError(e));
    return;
  }
  if (!context.mounted) return;
  final amount = order['amount_inr'] as num;
  if (shownPriceInr != null && amount != shownPriceInr && !await confirmPriceChange(context, amount)) return;
  if (!context.mounted) return;

  final uri = buildUpiUri(upiId: order['upi_id'] as String, payee: order['payee_name'] as String,
      reference: order['reference'] as String, amountInr: amount);
  UpiLaunch res;
  try {
    res = await app.upi.pay(uri);
  } on PlatformException catch (e) {
    if (context.mounted) toast(context, e.message ?? 'Could not open UPI');
    return;
  }
  if (!context.mounted) return;
  if (res.noApp) {
    await showNoUpiAppSheet(context, upiId: order['upi_id'] as String, amount: amount,
        reference: order['reference'] as String, payee: order['payee_name'] as String?, uri: uri);
    if (!context.mounted) return;
  } else {
    // save locally FIRST, then report (retried on resume/launch until the server answers)
    await app.queue.add(order['order_id'] as String, res.response ?? (res.cancelled ? 'Status=CANCELLED' : 'Status=NO_RESPONSE'));
    await app.flushPayments();
  }
  if (!context.mounted) return;
  await Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentStatusScreen(orderId: order['order_id'] as String, uri: uri)));
}

Future<bool> confirmPriceChange(BuildContext context, num amount) async =>
    await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text('Price updated to ${rupees(amount)}'),
      content: const Text('The price changed since this page loaded. Continue with the new price?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text('Pay ${rupees(amount)}')),
      ],
    )) ==
    true;

/// No UPI app opened (ActivityNotFoundException) — or the buyer chose "Pay with QR code":
/// QR of the same upi:// link, UPI ID / amount / reference with Copy.
Future<void> showNoUpiAppSheet(BuildContext context, {required String upiId, required num amount, required String reference,
    String? payee, String? uri, String title = 'No UPI app found'}) {
  final upi = AppScope.read(context).upi;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.surface,
    builder: (c) {
      Widget row(String label, String value) => ListTile(
            title: Text(label, style: const TextStyle(color: C.muted, fontSize: 13)),
            subtitle: Text(value, style: const TextStyle(color: C.text, fontSize: 16, fontWeight: FontWeight.w600)),
            trailing: TextButton(onPressed: () { Clipboard.setData(ClipboardData(text: value)); toast(c, '$label copied'); }, child: const Text('Copy')),
          );
      return SafeArea(child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(
            'Scan this code from any UPI app (on another phone too), or pay to the UPI ID below. '
            'You will pay ${rupees(amount)}${payee == null ? '' : ' to $payee'}.',
            style: const TextStyle(color: C.muted))),
        if (uri != null)
          FutureBuilder<List<int>?>(
            future: upi.qr(uri),
            builder: (_, s) => s.data == null ? const SizedBox(height: 8) : Center(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Semantics(label: 'UPI QR code for ${rupees(amount)}',
                  child: Image.memory(Uint8ListX.from(s.data!), width: 220, height: 220, filterQuality: FilterQuality.none)),
            )),
          ),
        row('UPI ID', upiId),
        row('Amount', amount.toStringAsFixed(2)),
        row('Reference', reference),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Put the reference in the payment note. After paying, tap "I have paid" and enter the 12-digit UTR.',
            style: TextStyle(color: C.muted, fontSize: 13))),
        Padding(padding: const EdgeInsets.all(16), child: FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Done'))),
      ])));
    },
  );
}

/// "I have paid": 12-digit UTR (+ optional screenshot) → server → verification.
Future<bool> showPaymentProofSheet(BuildContext context, {required String reference}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.surface,
      builder: (_) => PaymentProofSheet(reference: reference),
    ) ==
    true;

class PaymentProofSheet extends StatefulWidget {
  const PaymentProofSheet({super.key, required this.reference});
  final String reference;
  @override
  State<PaymentProofSheet> createState() => _PaymentProofSheetState();
}

class _PaymentProofSheetState extends State<PaymentProofSheet> {
  final _utr = TextEditingController();
  String? _shotName, _shotExt;
  List<int>? _shotBytes;
  bool _busy = false;
  String? _error;

  String get _digits => _utr.text.replaceAll(RegExp(r'\s'), '');
  bool get _valid => RegExp(r'^\d{12}$').hasMatch(_digits);

  Future<void> _pick() async {
    final f = await FilePicker.pickFile(type: FileType.image);
    if (f == null) return;
    final bytes = await f.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      if (mounted) setState(() => _error = 'Screenshot is larger than 5 MB.');
      return;
    }
    if (mounted) setState(() { _shotName = f.name; _shotExt = f.extension; _shotBytes = bytes; _error = null; });
  }

  Future<void> _submit() async {
    final api = AppScope.read(context).api;
    setState(() { _busy = true; _error = null; });
    try {
      String? key;
      final bytes = _shotBytes;
      if (bytes != null) {
        final ext = (_shotExt ?? 'jpg').toLowerCase();
        key = await api.uploadPaymentProof(widget.reference, _shotName ?? 'screenshot.$ext', bytes,
            ext == 'png' ? 'image/png' : ext == 'webp' ? 'image/webp' : 'image/jpeg');
      }
      final r = await api.submitPaymentProof(widget.reference, _digits, screenshotKey: key);
      if (r['error'] != null) {
        setState(() => _error = _friendlyProofError(r['error'] as String));
      } else if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('I have paid', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('Enter the 12-digit UTR / UPI reference number from your UPI app (open the payment in its history).',
              style: TextStyle(color: C.muted)),
          const SizedBox(height: 16),
          TextField(
            controller: _utr,
            keyboardType: TextInputType.number,
            maxLength: 14,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]'))],
            decoration: const InputDecoration(labelText: 'UTR (12 digits)', counterText: ''),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pick,
            icon: Icon(_shotBytes == null ? Icons.add_photo_alternate_outlined : Icons.check_circle, color: _shotBytes == null ? null : C.success),
            label: Text(_shotBytes == null ? 'Add payment screenshot (optional)' : _shotName ?? 'Screenshot', maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: C.dangerText))),
          const SizedBox(height: 16),
          GradientButton(label: _busy ? 'Sending…' : 'Send for verification', onPressed: _busy || !_valid ? null : _submit),
        ])),
      );
}

String _friendlyProofError(String e) => switch (e) {
      'this UTR was already used for another payment' => 'This UTR was already used for another payment. Check the number.',
      _ => e[0].toUpperCase() + e.substring(1),
    };

class PaymentStatusScreen extends StatefulWidget {
  const PaymentStatusScreen({super.key, required this.orderId, this.uri});
  final String orderId;
  final String? uri;
  @override
  State<PaymentStatusScreen> createState() => _PaymentStatusScreenState();
}

class _PaymentStatusScreenState extends State<PaymentStatusScreen> {
  String _status = 'pending';
  Json _order = const {};
  Timer? _t;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    _t = Timer.periodic(const Duration(seconds: 10), (_) { if (_status == 'pending' || _status == 'review') _check(); });
  }

  @override
  void dispose() { _t?.cancel(); super.dispose(); }

  Future<void> _check() async {
    final app = AppScope.read(context);
    await app.flushPayments();
    try {
      final r = await app.api.orderStatus(widget.orderId);
      if (r != null && mounted) setState(() { _status = r['status'] as String; _order = r; });
      if (_status == 'paid') await app.refresh();
    } catch (_) {}
  }

  String? get _ref => _order['reference'] as String?;

  Future<void> _proof() async {
    final ref = _ref;
    if (ref == null) return;
    if (await showPaymentProofSheet(context, reference: ref)) await _check();
  }

  Future<void> _qr() async {
    final o = _order;
    if (o['upi_id'] == null || _ref == null) return;
    final amount = o['amount_inr'] as num;
    await showNoUpiAppSheet(context, upiId: o['upi_id'] as String, amount: amount, reference: _ref!, payee: o['payee_name'] as String?,
        title: 'Pay with QR code',
        uri: widget.uri ?? buildUpiUri(upiId: o['upi_id'] as String, payee: o['payee_name'] as String? ?? '', reference: _ref!, amountInr: amount));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Payment status')),
        body: PaymentStatusView(status: _status, reference: _ref, utr: _order['utr'] as String?,
            amountInr: _order['amount_inr'] as num?, payee: _order['payee_name'] as String?,
            onCheck: _check, onTryAgain: () => Navigator.pop(context), onIHavePaid: _proof, onPayWithQr: _qr),
      );
}

/// Created → Waiting for payment → Verifying → Active, plus failure / expired states.
class PaymentStatusView extends StatelessWidget {
  const PaymentStatusView({super.key, required this.status, this.reference, this.utr, this.amountInr, this.payee,
      required this.onCheck, required this.onTryAgain, this.onIHavePaid, this.onPayWithQr});
  final String status;
  final String? reference, utr, payee;
  final num? amountInr;
  final VoidCallback onCheck, onTryAgain;
  final VoidCallback? onIHavePaid, onPayWithQr;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String text, String? sub) = switch (status) {
      'paid' => (Icons.check_circle, C.success, 'Payment successful! Your plan is now active.', null),
      'review' => (Icons.verified_user_outlined, C.primary, 'Payment received, being verified',
          'We check every payment against the bank. This usually takes a few hours.'),
      'expired' => (Icons.timer_off_outlined, C.warning, 'This order expired',
          'Orders stay open for 30 minutes. Start again — or if you already paid, tap "I have paid".'),
      'failed' || 'cancelled' => (Icons.error, C.danger, 'Payment failed or cancelled', 'No money was taken? Try again. Money was taken? Tap "I have paid".'),
      'rejected' => (Icons.error, C.danger, 'Payment could not be verified', 'Contact support with your UTR if money was taken.'),
      'revoked' => (Icons.block, C.danger, 'This payment was reversed', null),
      _ => (Icons.schedule, C.muted, 'Waiting for your payment', 'Finish the payment in your UPI app. Paid already? Tap "I have paid".'),
    };
    final step = switch (status) { 'paid' => 3, 'review' => 2, 'pending' => 1, _ => 0 };
    final canProve = onIHavePaid != null && (status == 'pending' || status == 'expired' || status == 'failed' || status == 'cancelled' ||
        (status == 'review' && utr == null));
    return ListView(padding: const EdgeInsets.all(20), children: [
      if (step > 0) ...[_Steps(step: step), const SizedBox(height: 24)],
      Center(child: Container(
        width: 88, height: 88,
        decoration: BoxDecoration(color: color.withValues(alpha: .12), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 48),
      )),
      const SizedBox(height: 16),
      Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      if (sub != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(sub, textAlign: TextAlign.center, style: const TextStyle(color: C.muted))),
      const SizedBox(height: 16),
      Card(child: Column(children: [
        if (amountInr != null) _kv('Amount', '${rupees(amountInr!)}${payee == null ? '' : ' to $payee'}'),
        if (reference != null) _kv('Reference', reference!),
        if (utr != null) _kv('UTR', utr!),
      ])),
      const SizedBox(height: 20),
      if (canProve) Padding(padding: const EdgeInsets.only(bottom: 10), child: GradientButton(label: 'I have paid', icon: Icons.receipt_long, onPressed: onIHavePaid)),
      if (status == 'pending' && onPayWithQr != null)
        Padding(padding: const EdgeInsets.only(bottom: 10), child: OutlinedButton.icon(onPressed: onPayWithQr, icon: const Icon(Icons.qr_code_2), label: const Text('Pay with QR code'))),
      if (status == 'pending' || status == 'review') OutlinedButton(onPressed: onCheck, child: const Text('Check again')),
      if (status == 'failed' || status == 'cancelled' || status == 'rejected' || status == 'expired')
        Padding(padding: const EdgeInsets.only(top: 10), child: canProve
            ? OutlinedButton(onPressed: onTryAgain, child: const Text('Try again'))
            : GradientButton(label: 'Try again', onPressed: onTryAgain)),
      if (status == 'paid' || status == 'review')
        Padding(padding: const EdgeInsets.only(top: 10),
            child: FilledButton(onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst), child: const Text('Done'))),
    ]);
  }

  static Widget _kv(String k, String v) => ListTile(dense: true, title: Text(k, style: const TextStyle(color: C.muted)),
      trailing: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 220),
          child: Text(v, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600, color: C.text))));
}

class _Steps extends StatelessWidget {
  const _Steps({required this.step});
  final int step; // 1 waiting, 2 verifying, 3 active
  @override
  Widget build(BuildContext context) {
    const labels = ['Created', 'Waiting for payment', 'Verifying', 'Active'];
    return Semantics(
      label: 'Step ${step + 1} of 4: ${labels[step]}',
      excludeSemantics: true,
      child: Row(children: [
        for (var i = 0; i < labels.length; i++) ...[
          Expanded(child: Column(children: [
            Container(height: 6, decoration: BoxDecoration(color: i <= step ? C.primary : C.border, borderRadius: BorderRadius.circular(6))),
            const SizedBox(height: 6),
            Text(labels[i], textAlign: TextAlign.center, maxLines: 2,
                style: TextStyle(fontSize: 11, color: i <= step ? C.text : C.muted, fontWeight: i == step ? FontWeight.w700 : FontWeight.w400)),
          ])),
          if (i < labels.length - 1) const SizedBox(width: 6),
        ],
      ]),
    );
  }
}

class PaymentHistoryScreen extends StatelessWidget {
  const PaymentHistoryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final api = AppScope.read(context).api;
    return Scaffold(
      appBar: AppBar(title: const Text('Payment history')),
      body: FutureBuilder<List<Json>>(
        future: api.paymentHistory(),
        builder: (_, s) {
          if (s.hasError) return const EmptyState(icon: Icons.cloud_off, title: 'Could not load payments');
          if (!s.hasData) return const SkeletonList(count: 4);
          if (s.data!.isEmpty) return const EmptyState(icon: Icons.receipt_long, title: 'No payments yet');
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: s.data!.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final o = s.data![i];
              final st = paymentStatusLabel(o['status'] as String);
              return Card(child: ListTile(
                title: Text('${(o['plans'] as Map?)?['name'] ?? 'Plan'} · ${rupees((o['amount_paise'] as num) / 100)}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text([
                  o['reference'],
                  if (o['utr'] != null) 'UTR ${o['utr']}',
                  formatDate(DateTime.tryParse(o['created_at'] as String)?.toLocal()),
                ].join(' · ')),
                trailing: Text(st.$1, style: TextStyle(color: st.$2, fontWeight: FontWeight.w600)),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentStatusScreen(orderId: o['id'] as String))),
              ));
            },
          );
        },
      ),
    );
  }
}

(String, Color) paymentStatusLabel(String s) => switch (s) {
      'paid' => ('Paid', C.successText),
      'review' => ('Verifying', C.primary),
      'pending' || 'submitted' => ('Waiting', C.muted),
      'expired' => ('Expired', C.warningText),
      'revoked' => ('Reversed', C.dangerText),
      'rejected' => ('Not verified', C.dangerText),
      _ => ('Failed', C.dangerText),
    };
