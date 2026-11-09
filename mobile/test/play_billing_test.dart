import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skykeep/screens/premium.dart';
import 'package:skykeep/services/play_billing.dart';
import 'package:skykeep/services/status.dart';
import 'package:skykeep/services/upi.dart';

import 'fakes.dart';

const _catalog = [
  {'plan_id': planMonthly, 'name': 'Monthly', 'perks': ['2 TB cloud', 'Full videos'], 'badge': 'Popular',
   'duration_days': 30, 'product_id': 'skykeep_monthly', 'base_plan_id': 'monthly'},
];

Widget _view(FakeApi api) => Scaffold(body: PlayPlansView(status: AppStatus.fromServer(api.status, null)));

void main() {
  test('Play build shows Play plans only when the server turned Play billing on', () {
    expect(premiumMode(const AppStatus(playBillingEnabled: false, plansVisible: true), playStore: true), PremiumMode.freeAccount);
    expect(premiumMode(const AppStatus(playBillingEnabled: true, plansVisible: true), playStore: true), PremiumMode.playBilling);
    expect(premiumMode(const AppStatus(playBillingEnabled: true, plansVisible: true, freeMode: true), playStore: false), PremiumMode.freeAccount);
  });

  testWidgets('Play plans: names and perks from the server, no own prices, no web page', (t) async {
    final api = FakeApi()..playCatalogList = _catalog;
    await pumpApp(t, api, _view(api));
    expect(find.text('Monthly'), findsOneWidget);
    expect(find.text('2 TB cloud'), findsOneWidget);
    expect(find.text('Popular'), findsOneWidget);
    expect(find.textContaining('₹'), findsNothing);
    expect(find.byKey(const Key('fake-web')), findsNothing);
  });

  testWidgets('Play plans: empty catalog (plans hidden for this user) → no buy prompts', (t) async {
    final api = FakeApi();
    await pumpApp(t, api, _view(api));
    expect(find.text('Subscribe'), findsNothing);
    expect(find.text('Premium videos and downloads are for Premium members.'), findsOneWidget);
  });

  testWidgets('Subscribe launches Google Play billing with the base plan and the hashed account id', (t) async {
    final api = FakeApi()..playCatalogList = _catalog;
    final play = FakePlay();
    await pumpApp(t, api, _view(api), play: play);
    await t.tap(find.text('Subscribe'));
    await t.pumpAndSettle();
    expect(play.bought.single, ['skykeep_monthly', 'monthly', 'a' * 64]);
  });

  testWidgets('Google Play path: purchase is sent to the server for verification', (t) async {
    final api = FakeApi()..playCatalogList = _catalog;
    final play = FakePlay();
    await pumpApp(t, api, _view(api), play: play);
    await t.tap(find.text('Subscribe'));
    await t.pumpAndSettle();
    play.onPurchases!('ok', const [
      PlayPurchase(productId: 'skykeep_monthly', purchaseToken: 'tok-1'),
      PlayPurchase(productId: 'skykeep_monthly', purchaseToken: 'tok-2', state: 'pending'),
    ]);
    await t.pumpAndSettle();
    expect(api.playRecorded.single, [{'productId': 'skykeep_monthly', 'purchaseToken': 'tok-1'}],
        reason: 'only completed purchases are sent; pending ones wait');
  });

  testWidgets('User Choice "Pay with UPI": state picker → UCB order with Google token → native UPI', (t) async {
    final api = FakeApi()..playCatalogList = _catalog;
    final play = FakePlay();
    final upi = FakeUpi(const UpiLaunch(response: 'Status=SUCCESS&txnId=ABC123456&txnRef=SK20261109PLAY0001'));
    await pumpApp(t, api, _view(api), play: play, upi: upi);
    await t.tap(find.text('Subscribe'));
    await t.pumpAndSettle();
    play.onUserChoice!('ext-token-123', const ['skykeep_monthly']);
    await t.pumpAndSettle();
    expect(find.text('Your state'), findsOneWidget);
    await t.tap(find.text('Assam'));
    await t.pumpAndSettle();
    expect(api.playChoiceOrders.single, [planMonthly, 'ext-token-123', 'AS']);
    expect(upi.lastUri, contains('tr=SK20261109PLAY0001'));
    expect(api.reported.single, contains('Status=SUCCESS'), reason: 'result reported through the normal queue');
  });

  testWidgets('Guest must log in before subscribing', (t) async {
    final api = FakeApi(guest: true)..playCatalogList = _catalog;
    final play = FakePlay();
    await pumpApp(t, api, _view(api), play: play);
    await t.tap(find.text('Subscribe'));
    await t.pumpAndSettle();
    expect(play.bought, isEmpty);
  });

  test('every Indian state code is unique and two letters', () {
    final codes = indianStates.map((e) => e.$1).toList();
    expect(codes.toSet().length, codes.length);
    expect(codes.every((c) => RegExp(r'^[A-Z]{2}$').hasMatch(c)), isTrue);
  });
}
