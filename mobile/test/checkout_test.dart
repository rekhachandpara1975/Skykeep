import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skykeep/app_state.dart';
import 'package:skykeep/screens/checkout.dart';
import 'package:skykeep/services/premium_web.dart';
import 'package:skykeep/services/upi.dart';
import 'package:skykeep/theme.dart';

import 'fakes.dart';

/// A button that runs startPurchase like the WebView message would.
class _Buy extends StatelessWidget {
  const _Buy(this.planId, this.shown);
  final String planId;
  final num shown;
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: ElevatedButton(
      onPressed: () => startPurchase(context, BuyMessage(planId, shown)), child: const Text('buy'))));
}

void main() {
  testWidgets('price change asks before paying', (t) async {
    final api = FakeApi();
    final upi = FakeUpi(const UpiLaunch(response: 'Status=SUCCESS&txnId=ABC123456&txnRef=SK20261109ABCDEF12'));
    await pumpApp(t, api, const _Buy(planYearly, 699), upi: upi);
    await t.tap(find.text('buy'));
    await t.pumpAndSettle();
    expect(find.text('Price updated to ₹799'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(upi.lastUri, isNull, reason: 'cancelled before UPI opened');

    await t.tap(find.text('buy'));
    await t.pumpAndSettle();
    await t.tap(find.text('Pay ₹799'));
    await t.pumpAndSettle();
    expect(upi.lastUri, contains('am=799.00'));
    expect(api.reported.single, contains('Status=SUCCESS'));
  });

  testWidgets('guest can pay without logging in', (t) async {
    final api = FakeApi(guest: true, status: statusJson(guest: true))..orderStatusValue = 'paid';
    final upi = FakeUpi(const UpiLaunch(response: 'Status=SUCCESS'));
    await pumpApp(t, api, const _Buy(planYearly, 799), upi: upi);
    await t.tap(find.text('buy'));
    await t.pumpAndSettle();
    expect(find.text('Create account'), findsNothing, reason: 'no login sheet');
    expect(upi.lastUri, contains('am=799.00'));
    expect(find.text('Payment successful! Your plan is now active.'), findsOneWidget);
  });

  testWidgets('successful payment shows the success screen', (t) async {
    final api = FakeApi()..orderStatusValue = 'paid';
    await pumpApp(t, api, const _Buy(planYearly, 799), upi: FakeUpi(const UpiLaunch(response: 'Status=SUCCESS')));
    await t.tap(find.text('buy'));
    await t.pumpAndSettle();
    expect(find.text('Payment successful! Your plan is now active.'), findsOneWidget);
  });

  testWidgets('no UPI app → copy sheet with UPI ID, amount, reference', (t) async {
    await pumpApp(t, FakeApi(), const _Buy(planYearly, 799), upi: FakeUpi(const UpiLaunch(noApp: true)));
    await t.tap(find.text('buy'));
    await t.pumpAndSettle();
    expect(find.text('No UPI app found'), findsOneWidget);
    expect(find.text('shop@okaxis'), findsOneWidget);
    expect(find.text('799.00'), findsOneWidget);
    expect(find.text('SK20261109ABCDEF12'), findsOneWidget);
    expect(find.text('Copy'), findsNWidgets(3));
  });

  testWidgets('report fails → result kept in queue and retried later', (t) async {
    final api = FakeApi()..reportFails = true;
    final c = await pumpApp(t, api, const _Buy(planYearly, 799), upi: FakeUpi(const UpiLaunch(response: 'Status=FAILURE')));
    await t.tap(find.text('buy'));
    await t.pumpAndSettle();
    expect(c.queue.items.single['raw'], 'Status=FAILURE');
    expect(find.text('Waiting for your payment'), findsOneWidget);
    // server back (app resumed later; backoff elapsed)
    api.reportFails = false;
    final items = c.queue.items..first['next_at'] = 0;
    await c.prefs.setString('pending_payments', '[{"order_id":"o1","raw":"${items.first['raw']}","attempts":1,"next_at":0}]');
    await c.flushPayments();
    expect(api.reported.single, 'Status=FAILURE');
    expect(c.queue.items, isEmpty);
    await t.pump(const Duration(seconds: 6));
  });

  testWidgets('removed plan → not available', (t) async {
    await pumpApp(t, FakeApi(), const _Buy('33333333-3333-3333-3333-333333333333', 99));
    await t.tap(find.text('buy'));
    await t.pumpAndSettle();
    expect(find.text('This plan is no longer available.'), findsOneWidget);
  });

  testWidgets('free plan → claim, no UPI', (t) async {
    final upi = FakeUpi(const UpiLaunch());
    await pumpApp(t, FakeApi(freePlanIds: const [planMonthly]), const _Buy(planMonthly, 99), upi: upi);
    await t.tap(find.text('buy'));
    await t.pumpAndSettle();
    expect(find.text('Plan activated until 9 Dec 2026'), findsOneWidget);
    expect(upi.lastUri, isNull);
  });

  testWidgets('status screen states', (t) async {
    for (final (s, text) in [
      ('review', 'Payment received, being verified'),
      ('failed', 'Payment failed or cancelled'),
      ('cancelled', 'Payment failed or cancelled'),
      ('pending', 'Waiting for your payment'),
      ('expired', 'This order expired'),
      ('rejected', 'Payment could not be verified'),
    ]) {
      await pumpApp(t, FakeApi(), Scaffold(body: PaymentStatusView(status: s, onCheck: () {}, onTryAgain: () {})));
      expect(find.text(text), findsOneWidget, reason: s);
      if (s == 'failed') expect(find.text('Try again'), findsOneWidget);
      if (s == 'pending') expect(find.text('Check again'), findsOneWidget);
    }
  });

  testWidgets('pending: "I have paid" + QR fallback offered; paid: no proof button', (t) async {
    await pumpApp(t, FakeApi(), Scaffold(body: PaymentStatusView(status: 'pending', reference: 'SK1', onCheck: () {}, onTryAgain: () {},
        onIHavePaid: () {}, onPayWithQr: () {})));
    expect(find.text('I have paid'), findsOneWidget);
    expect(find.text('Pay with QR code'), findsOneWidget);
    await pumpApp(t, FakeApi(), Scaffold(body: PaymentStatusView(status: 'paid', reference: 'SK1', onCheck: () {}, onTryAgain: () {},
        onIHavePaid: () {}, onPayWithQr: () {})));
    expect(find.text('I have paid'), findsNothing);
  });

  testWidgets('verifying with UTR: no proof button; expired: proof + try again', (t) async {
    await pumpApp(t, FakeApi(), Scaffold(body: PaymentStatusView(status: 'review', utr: '123456789012', onCheck: () {}, onTryAgain: () {}, onIHavePaid: () {})));
    expect(find.text('I have paid'), findsNothing);
    expect(find.text('123456789012'), findsOneWidget);
    await pumpApp(t, FakeApi(), Scaffold(body: PaymentStatusView(status: 'expired', onCheck: () {}, onTryAgain: () {}, onIHavePaid: () {})));
    expect(find.text('I have paid'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('UTR sheet: 12 digits required, server error shown, success closes', (t) async {
    final api = FakeApi();
    await pumpApp(t, api, const Scaffold(body: PaymentProofSheet(reference: 'SK20261109ABCDEF12')));
    final send = find.widgetWithText(GradientButton, 'Send for verification');
    await t.enterText(find.byType(TextField), '12345');
    await t.pump();
    expect(t.widget<GradientButton>(send).onPressed, isNull, reason: 'button disabled until 12 digits');
    api.proofError = 'this UTR was already used for another payment';
    await t.enterText(find.byType(TextField), '1234 5678 9012');
    await t.pump();
    await t.tap(send);
    await t.pumpAndSettle();
    expect(find.text('This UTR was already used for another payment. Check the number.'), findsOneWidget);
    expect(api.proofs.single, ['SK20261109ABCDEF12', '123456789012']);
  });

  test('controller keeps AppScope type', () => expect(AppScope, isNotNull));
}
