import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skykeep/screens/profile.dart';
import 'package:skykeep/version.dart';

import 'fakes.dart';

void main() {
  test('version label matches pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final v = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec)!.group(1);
    expect(appVersion, v, reason: 'update lib/version.dart when you bump pubspec.yaml');
  });

  testWidgets('Settings shows the real version', (t) async {
    await pumpApp(t, FakeApi(), const SettingsScreen());
    expect(find.text('Version $appVersion'), findsOneWidget);
  });
}
