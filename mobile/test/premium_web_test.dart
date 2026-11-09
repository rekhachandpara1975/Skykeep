import 'package:flutter_test/flutter_test.dart';
import 'package:skykeep/services/premium_web.dart';
import 'package:skykeep/services/status.dart';

const base = 'https://skykeep.vercel.app';

void main() {
  test('plans page URL params', () {
    expect(premiumPageUrl(freePlanIds: const [], paymentsAvailable: true).toString(), '$base/subscribe?app=1');
    expect(premiumPageUrl(freePlanIds: const ['a', 'b'], paymentsAvailable: true).queryParameters, {'app': '1', 'free': 'a,b'});
    expect(premiumPageUrl(freePlanIds: const [], paymentsAvailable: false).queryParameters, {'app': '1', 'paused': '1'});
  });

  test('navigation allowlist', () {
    expect(allowWebNavigation('$base/subscribe?app=1'), isTrue);
    expect(allowWebNavigation('$base/d'), isTrue);
    expect(allowWebNavigation('$base/'), isFalse);
    expect(allowWebNavigation('$base/admin'), isFalse);
    expect(allowWebNavigation('http://skykeep.vercel.app/subscribe'), isFalse);
    expect(allowWebNavigation('https://evil.example/subscribe'), isFalse);
    expect(allowWebNavigation('https://skykeep.vercel.app.evil.example/subscribe'), isFalse);
    expect(allowWebNavigation('upi://pay?pa=x'), isFalse);
  });

  test('buy message parsing', () {
    const id = '11111111-1111-1111-1111-111111111111';
    expect(parseBuyMessage('{"type":"buy","plan_id":"$id"}')?.planId, id);
    expect(parseBuyMessage('{"type":"buy","plan_id":"$id","price_inr":99}')?.shownPriceInr, 99);
    expect(parseBuyMessage('{"type":"other","plan_id":"$id"}'), isNull);
    expect(parseBuyMessage('{"type":"buy","plan_id":"not-a-uuid"}'), isNull);
    expect(parseBuyMessage('not json'), isNull);
    expect(parseBuyMessage('[1,2]'), isNull);
  });

  test('premium mode per build and status', () {
    const paid = AppStatus(plansVisible: true, loaded: true);
    expect(premiumMode(paid, playStore: false), PremiumMode.web);
    expect(premiumMode(const AppStatus(freeMode: true, plansVisible: false), playStore: false), PremiumMode.freeAccount);
    expect(premiumMode(const AppStatus(plansVisible: false), playStore: false), PremiumMode.hidden);
    // Play build never shows the web plans / UPI
    expect(premiumMode(paid, playStore: true), PremiumMode.freeAccount);
    expect(premiumMode(const AppStatus(plansVisible: true, playBillingEnabled: true), playStore: true), PremiumMode.playBilling);
  });

  test('rupees with Indian grouping', () {
    expect(rupees(99), '₹99');
    expect(rupees(123456), '₹1,23,456');
    expect(rupees(12345678.5), '₹1,23,45,678.50');
  });
}
