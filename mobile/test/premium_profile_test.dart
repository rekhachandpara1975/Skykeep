import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skykeep/screens/premium.dart';
import 'package:skykeep/screens/profile.dart';

import 'fakes.dart';
import 'flutter_test_config.dart';

void main() {
  group('Premium', () {
    testWidgets('guest in free mode: log in for 15 GB, no prices', (t) async {
      await pumpApp(t, FakeApi(guest: true, status: statusJson(guest: true, freeMode: true, plansVisible: false)), const PremiumScreen());
      expect(find.text('Log in to get 15 GB free cloud storage.'), findsOneWidget);
      expect(find.textContaining('₹'), findsNothing);
      expect(find.byKey(const Key('fake-web')), findsNothing);
    });

    testWidgets('organic member in free mode: storage meter + request full access', (t) async {
      await pumpApp(t, FakeApi(status: statusJson(source: 'organic', freeMode: true, plansVisible: false, quota: 16106127360)), const PremiumScreen());
      expect(find.textContaining('of 15.0 GB used'), findsOneWidget);
      expect(find.text('Request full access'), findsOneWidget);
    });

    testWidgets('organic pending / rejected states', (t) async {
      await pumpApp(t, FakeApi(status: statusJson(source: 'organic', freeMode: true, plansVisible: false, access: 'pending')), const PremiumScreen());
      expect(find.text('Full access requested — waiting for approval'), findsOneWidget);
    });

    testWidgets('plans hidden: no web page, no prices, premium members message', (t) async {
      await pumpApp(t, FakeApi(status: statusJson(plansVisible: false)), const PremiumScreen());
      expect(find.byKey(const Key('fake-web')), findsNothing);
      expect(find.text('Premium videos and downloads are for Premium members.'), findsOneWidget);
      expect(find.textContaining('₹'), findsNothing);
    });

    testWidgets('plans hidden but subscriber still sees plan', (t) async {
      await pumpApp(t, FakeApi(status: statusJson(plansVisible: false, hasPlan: true, premium: true)), const PremiumScreen());
      expect(find.text('Yearly active until 9 Nov 2027'), findsOneWidget);
      expect(find.text('Payment history'), findsOneWidget);
    });

    testWidgets('plans visible: website plans page with free / paused params', (t) async {
      await pumpApp(t, FakeApi(status: statusJson(paymentsAvailable: false), freePlanIds: const [planMonthly]), const PremiumScreen());
      expect(find.text('Go Premium'), findsOneWidget);
      expect(find.byKey(const Key('fake-web')), findsNothing, reason: 'plans page opens from "View plans"');
      await t.tap(find.text('View plans'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('fake-web')), findsOneWidget);
      expect(FakePremiumWeb.lastUrl!.queryParameters, {'app': '1', 'free': planMonthly, 'paused': '1'});
    });

    testWidgets('subscriber sees active-plan banner above the page', (t) async {
      await pumpApp(t, FakeApi(status: statusJson(hasPlan: true, premium: true)), const PremiumScreen());
      expect(find.text('Yearly active until 9 Nov 2027'), findsOneWidget);
      await t.tap(find.text('View plans'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('fake-web')), findsOneWidget);
      expect(find.text('Yearly active until 9 Nov 2027'), findsOneWidget, reason: 'banner above the plans page');
    });
  });

  group('Profile', () {
    testWidgets('guest: log in button, plans first when visible', (t) async {
      await pumpApp(t, FakeApi(guest: true, status: statusJson(guest: true)), const ProfileScreen());
      expect(find.text('Go Premium'), findsOneWidget);
      expect(find.text('Log in or create account'), findsOneWidget);
    });

    testWidgets('member without plan, plans visible: Premium first', (t) async {
      await pumpApp(t, FakeApi(status: statusJson()), const ProfileScreen());
      final premium = t.getTopLeft(find.text('Go Premium')).dy;
      final account = t.getTopLeft(find.text('Asha')).dy;
      expect(premium, lessThan(account));
      expect(find.text('Free account'), findsOneWidget);
    });

    testWidgets('subscriber: plan line, no Premium tile', (t) async {
      await pumpApp(t, FakeApi(status: statusJson(hasPlan: true, premium: true, quota: 2199023255552)), const ProfileScreen());
      expect(find.text('Go Premium'), findsNothing);
      expect(find.text('Yearly active until 9 Nov 2027'), findsOneWidget);
      expect(find.text('Payment history'), findsOneWidget);
    });

    testWidgets('plans hidden: no Premium tile, no payment history', (t) async {
      await pumpApp(t, FakeApi(status: statusJson(plansVisible: false)), const ProfileScreen());
      expect(find.text('Go Premium'), findsNothing);
      expect(find.text('Payment history'), findsNothing);
    });

    testWidgets('free mode: full access status, no Premium tile', (t) async {
      await pumpApp(t, FakeApi(status: statusJson(freeMode: true, plansVisible: false, premium: true, quota: 16106127360)), const ProfileScreen());
      expect(find.text('Go Premium'), findsNothing);
      expect(find.text('Full access'), findsWidgets);
    });
  });
}
