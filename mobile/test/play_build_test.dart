// Run with: flutter test --dart-define=PLAY_STORE=true test/play_build_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skykeep/config.dart';
import 'package:skykeep/screens/cloud.dart';
import 'package:skykeep/screens/explore.dart';
import 'package:skykeep/screens/premium.dart';
import 'package:skykeep/screens/profile.dart';

import 'fakes.dart';

void main() {
  final skip = !Config.playStore || Config.sellsPlans ? 'needs --dart-define=PLAY_STORE=true (without PLAY_SELLS_UPI)' : null;

  testWidgets('Play build: no crown, no Premium tile, no prices, no web plans', (t) async {
    final api = FakeApi(status: statusJson(plansVisible: true, paymentsAvailable: true));
    await pumpApp(t, api, const ExploreScreen());
    expect(find.byTooltip('Premium'), findsNothing);
    await pumpApp(t, api, const ProfileScreen());
    expect(find.text('Go Premium'), findsNothing);
    expect(find.textContaining('₹'), findsNothing);
    await pumpApp(t, api, const PremiumScreen());
    expect(find.byKey(const Key('fake-web')), findsNothing);
    expect(find.text('Free account'), findsOneWidget);
    await pumpApp(t, api, const CloudScreen());
    expect(find.text('See Premium'), findsNothing);
  }, skip: skip != null);

  test('Play build uses the Play package for the login callback', () {
    expect(Config.authCallback, 'com.skykeep.play://login-callback');
  }, skip: skip);
}
