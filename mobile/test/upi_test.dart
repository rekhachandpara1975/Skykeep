import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skykeep/services/upi.dart';

void main() {
  test('builds the UPI intent URI', () {
    final uri = buildUpiUri(upiId: 'shop@okaxis', payee: 'SkyKeep Shop & Co', reference: 'SK20261109ABCDEF12', amountInr: 99);
    expect(uri, 'upi://pay?pa=shop%40okaxis&pn=SkyKeep%20Shop%20%26%20Co&tr=SK20261109ABCDEF12&am=99.00&cu=INR&tn=SkyKeep%20SK20261109ABCDEF12');
    expect(buildUpiUri(upiId: 'a@b', payee: 'P', reference: 'R', amountInr: 249.5), contains('am=249.50'));
  });

  group('parses UPI results', () {
    test('SUCCESS (any case)', () {
      final r = parseUpiResult('txnId=ABC123456&responseCode=00&Status=SUCCESS&txnRef=SK1');
      expect(r.outcome, UpiOutcome.success);
      expect(r.txnId, 'ABC123456');
      expect(r.txnRef, 'SK1');
      expect(parseUpiResult('status=success&txnref=SK1').outcome, UpiOutcome.success);
    });
    test('FAILURE', () => expect(parseUpiResult('Status=FAILURE&txnRef=SK1').outcome, UpiOutcome.failure));
    test('NO_RESPONSE / empty', () {
      expect(parseUpiResult('Status=NO_RESPONSE').outcome, UpiOutcome.noResponse);
      expect(parseUpiResult(null).outcome, UpiOutcome.noResponse);
      expect(parseUpiResult('  ').outcome, UpiOutcome.noResponse);
    });
    test('garbage', () {
      expect(parseUpiResult('%%%garbage').outcome, UpiOutcome.unknown);
      expect(parseUpiResult('Status=WHATEVER').outcome, UpiOutcome.unknown);
    });
  });

  group('pending payments queue', () {
    late SharedPreferences prefs;
    var now = DateTime(2026, 11, 9, 12);
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      now = DateTime(2026, 11, 9, 12);
    });

    test('saves first, reports, then clears', () async {
      final q = PendingPaymentsQueue(prefs, now: () => now);
      await q.add('o1', 'Status=SUCCESS');
      expect(q.items, hasLength(1));
      final r = await q.flush((id, raw) async => 'paid');
      expect(r, {'o1': 'paid'});
      expect(q.items, isEmpty);
    });

    test('keeps the result and backs off until the server answers', () async {
      final q = PendingPaymentsQueue(prefs, now: () => now);
      await q.add('o1', 'Status=SUCCESS');
      expect(await q.flush((_, _) async => throw Exception('offline')), isEmpty);
      expect(q.items.single['attempts'], 1);
      // not due yet → not retried
      var calls = 0;
      await q.flush((_, _) async { calls++; return 'paid'; });
      expect(calls, 0);
      // app killed and relaunched later: a new queue over the same storage retries
      now = now.add(const Duration(seconds: 3));
      final q2 = PendingPaymentsQueue(prefs, now: () => now);
      expect(await q2.flush((_, _) async => 'paid'), {'o1': 'paid'});
      expect(q2.items, isEmpty);
    });
  });
}
