// Run with: flutter test --dart-define=PLAY_STORE=true --dart-define=PLAY_SELLS_UPI=true test/play_upi_build_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:skykeep/config.dart';
import 'package:skykeep/screens/premium.dart';

import 'fakes.dart';

void main() {
  final skip = !(Config.playStore && Config.sellsPlans);

  testWidgets('Play build with UPI plans: Premium shows the plans page', (t) async {
    final api = FakeApi(status: statusJson(plansVisible: true, paymentsAvailable: true));
    await pumpApp(t, api, const PremiumScreen());
    expect(find.text('Free account'), findsNothing);
    expect(find.text('View plans'), findsOneWidget);
  }, skip: skip);

  test('still the Play package', () {
    expect(Config.authCallback, 'com.skykeep.play://login-callback');
  }, skip: skip);
}
