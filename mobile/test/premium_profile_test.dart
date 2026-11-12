import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skykeep/screens/premium.dart';
import 'package:skykeep/screens/plans.dart';
import 'package:skykeep/screens/profile.dart';

import 'fakes.dart';

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

    testWidgets('plans visible: native plan picker, free plan and paused payments', (t) async {
      await pumpApp(t, FakeApi(status: statusJson(paymentsAvailable: false), freePlanIds: const [planMonthly]), const PremiumScreen());
      expect(find.text('Go Premium'), findsOneWidget);
      expect(find.text('Choose your plan'), findsOneWidget);
      expect(find.text('Monthly'), findsOneWidget);
      expect(find.text('FREE'), findsOneWidget);
      expect(find.text('₹799'), findsOneWidget);
      expect(find.text('1 Year · ₹2.2 / day'), findsOneWidget);
      expect(find.text('Get Yearly · ₹799'), findsOneWidget);
      expect(find.text('Payments are paused right now. Please try again later.'), findsOneWidget);
      await t.tap(find.text('Monthly'));
      await t.pump();
      expect(find.text('Get Monthly · Free'), findsOneWidget);
      expect(find.byKey(const Key('fake-web')), findsNothing);
    });

    testWidgets('subscriber sees the plan, not the picker', (t) async {
      await pumpApp(t, FakeApi(status: statusJson(hasPlan: true, premium: true)), const PremiumScreen());
      expect(find.text('Yearly active until 9 Nov 2027'), findsOneWidget);
      expect(find.text('Choose your plan'), findsNothing);
      expect(find.text('Payment history'), findsOneWidget);
    });
  });

  group('Profile', () {
    testWidgets('guest: link your email, Go Premium, My cloud, log in', (t) async {
      await pumpApp(t, FakeApi(guest: true, status: statusJson(guest: true)), const ProfileScreen());
      expect(find.text('Link your email'), findsOneWidget);
      expect(find.text('Go Premium'), findsOneWidget);
      expect(find.text('My cloud'), findsOneWidget);
      expect(find.text('Log in or create account'), findsOneWidget);
      expect(find.text('My Channels'), findsOneWidget);
      expect(find.text('Add Channel'), findsOneWidget);
    });

    testWidgets('member without plan: Go Premium tile, no link-email banner', (t) async {
      await pumpApp(t, FakeApi(status: statusJson()), const ProfileScreen());
      expect(find.text('Go Premium'), findsOneWidget);
      expect(find.text('Link your email'), findsNothing);
      expect(find.text('Free account'), findsOneWidget);
    });

    testWidgets('subscriber: My plan tile and plan line', (t) async {
      await pumpApp(t, FakeApi(status: statusJson(hasPlan: true, premium: true, quota: 2199023255552)), const ProfileScreen());
      expect(find.text('Go Premium'), findsNothing);
      expect(find.text('My plan'), findsOneWidget);
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

    testWidgets('settings: policy buttons, logout, delete account', (t) async {
      await pumpApp(t, FakeApi(status: statusJson()), const SettingsScreen());
      for (final x in ['Privacy Policy', 'Terms & Conditions', 'Community Guidelines', 'Refund Policy', 'Logout', 'Delete Account']) {
        expect(find.text(x), findsOneWidget, reason: x);
      }
    });
  });

  group('Guest purchases', () {
    testWidgets('guest with a payment under check sees the status card', (t) async {
      final api = FakeApi(guest: true, status: statusJson(guest: true))
        ..pendingOrderValue = {'id': 'o9', 'reference': 'SK20261112REVIEW01', 'status': 'review'};
      await pumpApp(t, api, const PremiumScreen());
      expect(find.text('Payment SK20261112REVIEW01 is being checked'), findsOneWidget);
    });
  });

  group('Avatar letter', () {
    test('never fails on empty names or emails', () {
      expect(avatarInitial(null, null), 'G');
      expect(avatarInitial('', ''), 'G');
      expect(avatarInitial('  ', ''), 'G');
      expect(avatarInitial('', 'asha@x.in'), 'A');
      expect(avatarInitial('ravi', null), 'R');
    });

    testWidgets('profile still draws when the name is empty', (t) async {
      final st = statusJson()..['display_name'] = '';
      await pumpApp(t, FakeApi(status: st), const ProfileScreen());
      expect(find.text('My cloud'), findsOneWidget);
      expect(find.text('Your account'), findsOneWidget);
    });
  });

  group('Plan labels', () {
    test('durations and unit prices', () {
      expect(planDuration({'duration_days': 2}), '2 Days');
      expect(planDuration({'duration_days': 30}), '1 Month');
      expect(planDuration({'duration_days': 180}), '6 Months');
      expect(planDuration({'duration_days': 365}), '1 Year');
      expect(planDuration({'duration_days': 1, 'duration_hours': 6}), '6 Hours');
      expect(planUnitPrice({'price_inr': 99, 'duration_days': 2}), '₹49.5 / day');
      expect(planUnitPrice({'price_inr': 30, 'duration_days': 1, 'duration_hours': 3}), '₹10 / hour');
    });
  });
}
