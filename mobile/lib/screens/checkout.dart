import 'dart:async';

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


Future<void> upiCheckout(BuildContext context, {required Json plan, required num shownPriceInr}) async {
  final app = AppScope.read(context);
  Json order;
  try {
    order = await app.api.createOrder(plan['id'] as String);
  } catch (e) {
    if (context.mounted) toast(context, friendlyError(e));
    return;
  }
  if (!context.mounted) return;
  final amount = order['amount_inr'] as num;
  if (amount != shownPriceInr && !await confirmPriceChange(context, amount)) return;
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
    await showNoUpiAppSheet(context, upiId: order['upi_id'] as String, amount: amount, reference: order['reference'] as String);
    if (!context.mounted) return;
  } else {
    // save locally FIRST, then report (retried on resume/launch until the server answers)
    await app.queue.add(order['order_id'] as String, res.response ?? (res.cancelled ? 'Status=CANCELLED' : 'Status=NO_RESPONSE'));
    await app.flushPayments();
  }
  if (!context.mounted) return;
  await Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentStatusScreen(orderId: order['order_id'] as String)));
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

/// Only shown on ActivityNotFoundException: pay by hand with these details.
Future<void> showNoUpiAppSheet(BuildContext context, {required String upiId, required num amount, required String reference}) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: C.surface,
      builder: (c) {
        Widget row(String label, String value) => ListTile(
              title: Text(label, style: const TextStyle(color: C.muted, fontSize: 13)),
              subtitle: Text(value, style: const TextStyle(color: C.text, fontSize: 16, fontWeight: FontWeight.w600)),
              trailing: TextButton(onPressed: () { Clipboard.setData(ClipboardData(text: value)); toast(c, '$label copied'); }, child: const Text('Copy')),
            );
        return SafeArea(child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text('No UPI app found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Pay from any UPI app on another phone using these details. Put the reference in the note.',
              style: TextStyle(color: C.muted))),
          row('UPI ID', upiId),
          row('Amount', amount.toStringAsFixed(2)),
          row('Reference', reference),
          Padding(padding: const EdgeInsets.all(16), child: FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Done'))),
        ])));
      },
    );

class PaymentStatusScreen extends StatefulWidget {
  const PaymentStatusScreen({super.key, required this.orderId});
  final String orderId;
  @override
  State<PaymentStatusScreen> createState() => _PaymentStatusScreenState();
}

class _PaymentStatusScreenState extends State<PaymentStatusScreen> {
  String _status = 'pending';
  String? _ref;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    _t = Timer.periodic(const Duration(seconds: 5), (_) { if (_status == 'pending') _check(); });
  }

  @override
  void dispose() { _t?.cancel(); super.dispose(); }

  Future<void> _check() async {
    final app = AppScope.read(context);
    await app.flushPayments();
    try {
      final r = await app.api.orderStatus(widget.orderId);
      if (r != null && mounted) setState(() { _status = r['status'] as String; _ref = r['reference'] as String?; });
      if (_status == 'paid') await app.refresh();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Payment')),
        body: PaymentStatusView(status: _status, reference: _ref, onCheck: _check, onTryAgain: () => Navigator.pop(context)),
      );
}

class PaymentStatusView extends StatelessWidget {
  const PaymentStatusView({super.key, required this.status, this.reference, required this.onCheck, required this.onTryAgain});
  final String status;
  final String? reference;
  final VoidCallback onCheck, onTryAgain;
  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String text) = switch (status) {
      'paid' => (Icons.check_circle, C.success, 'Payment successful! Your plan is now active.'),
      'review' => (Icons.hourglass_top, C.warning, 'Payment received, being verified'),
      'failed' || 'cancelled' || 'rejected' => (Icons.error, C.danger, 'Payment failed or cancelled'),
      'revoked' => (Icons.block, C.danger, 'This payment was reversed'),
      _ => (Icons.schedule, C.muted, 'Waiting for confirmation…'),
    };
    return ListView(padding: const EdgeInsets.all(24), children: [
      const SizedBox(height: 32),
      Icon(icon, color: color, size: 72),
      const SizedBox(height: 16),
      Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
      if (reference != null) Padding(padding: const EdgeInsets.only(top: 8),
          child: Text('Reference $reference', textAlign: TextAlign.center, style: const TextStyle(color: C.muted))),
      const SizedBox(height: 24),
      if (status == 'pending') OutlinedButton(onPressed: onCheck, child: const Text('Check again')),
      if (status == 'failed' || status == 'cancelled' || status == 'rejected') GradientButton(label: 'Try again', onPressed: onTryAgain),
      if (status == 'paid' || status == 'review') FilledButton(onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst), child: const Text('Done')),
    ]);
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
          if (!s.hasData) return const SkeletonList(count: 4);
          if (s.data!.isEmpty) return const EmptyState(icon: Icons.receipt_long, title: 'No payments yet');
          return ListView(children: [
            for (final o in s.data!)
              ListTile(
                title: Text('${(o['plans'] as Map?)?['name'] ?? 'Plan'} · ${rupees((o['amount_paise'] as num) / 100)}'),
                subtitle: Text('${o['reference']} · ${formatDate(DateTime.tryParse(o['created_at'] as String)?.toLocal())}'),
                trailing: Text(o['status'] == 'submitted' ? 'pending' : o['status'] as String),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentStatusScreen(orderId: o['id'] as String))),
              ),
          ]);
        },
      ),
    );
  }
}
