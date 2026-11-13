import 'package:flutter_test/flutter_test.dart';
import 'package:skykeep/widgets/pro_player.dart';

void main() {
  test('clock formats minutes and hours', () {
    expect(clock(Duration.zero), '00:00');
    expect(clock(const Duration(seconds: 75)), '01:15');
    expect(clock(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
    expect(clock(const Duration(seconds: -5)), '00:00');
  });

  test('speed labels and the offered speeds', () {
    expect(playbackSpeeds, [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]);
    expect([for (final s in playbackSpeeds) speedLabel(s)], ['0.5x', '0.75x', '1x', '1.25x', '1.5x', '2x']);
  });
}
