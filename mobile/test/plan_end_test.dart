import 'package:flutter_test/flutter_test.dart';
import 'package:skykeep/services/status.dart';

void main() {
  final now = DateTime(2026, 11, 12, 14, 0);
  test('hour plans show the end time', () {
    expect(formatPlanEnd(DateTime(2026, 11, 12, 20, 30), now: now), '12 Nov 2026, 8:30 PM');
    expect(formatPlanEnd(DateTime(2026, 11, 13, 0, 5), now: now), '13 Nov 2026, 12:05 AM');
  });
  test('long plans show only the date', () {
    expect(formatPlanEnd(DateTime(2026, 12, 12, 20, 30), now: now), '12 Dec 2026');
    expect(formatPlanEnd(null, now: now), '—');
  });
}
