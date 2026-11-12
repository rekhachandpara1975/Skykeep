// Google Play listing screenshots with real text and icons (not the block font tests normally use).
// CI runs: flutter test --update-goldens --dart-define=FONT_DIR=<flutter>/bin/cache/artifacts/material_fonts test/store
// Output: test/store/raw/*.png (1080 x 2340), framed later by tool/store_assets.py.
@Tags(['store'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skykeep/screens/channels.dart';
import 'package:skykeep/screens/checkout.dart';
import 'package:skykeep/screens/cloud.dart';
import 'package:skykeep/screens/home.dart';
import 'package:skykeep/screens/premium.dart';
import 'package:skykeep/screens/profile.dart';
import 'package:skykeep/screens/welcome.dart';
import 'package:skykeep/services/api.dart';

import '../fakes.dart';

const _fontDir = String.fromEnvironment('FONT_DIR');

Future<void> _loadFonts() async {
  final dir = Directory(_fontDir);
  // Styles that name no font fall back to the test font ("FlutterTest", drawn as blocks); on phones they use Roboto,
  // so register Roboto under both names.
  final roboto = FontLoader('Roboto');
  final fallback = FontLoader('FlutterTest');
  final icons = FontLoader('MaterialIcons');
  for (final f in dir.listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    final bytes = ByteData.sublistView(f.readAsBytesSync());
    if (name.startsWith('Roboto') && name.endsWith('.ttf')) {
      roboto.addFont(Future.value(bytes));
      fallback.addFont(Future.value(bytes));
    }
    if (name.startsWith('MaterialIcons')) icons.addFont(Future.value(bytes));
  }
  await roboto.load();
  await fallback.load();
  await icons.load();
}

final List<Json> _plans = [
  for (final (i, name, price, days, badge) in [
    (1, 'Trial', 69, 2, null),
    (2, 'Silver Plan', 129, 7, null),
    (3, 'Gold Plan', 259, 30, 'Popular'),
    (4, 'Platinum Plan', 599, 180, null),
    (5, 'Diamond Plan', 899, 365, 'Best value'),
  ])
    {'id': '0000000$i-0000-0000-0000-000000000000', 'name': name, 'price_inr': price, 'duration_days': days, 'badge': badge,
      'perks': ['2 TB storage', 'Full videos', 'Downloads']},
];

final _posts = [
  for (final (i, t, ch) in [
    (0, 'Sunrise trek to Kedarkantha — full vlog', 'Travel Diaries'),
    (1, '10-minute paneer tikka at home', 'Desi Kitchen'),
    (2, 'Phone storage full? Free up 20 GB today', 'SkyKeep Tips'),
  ])
    {'id': 'p$i', 'title': t, 'channels': {'name': ch}, 'post_items': [{'thumbnail_key': null, 'is_premium': i == 1}]},
];
final _channels = [
  {'id': 'c1', 'name': 'SkyKeep Tips', 'members_count': 12400, 'category': 'Tech', 'review_status': 'approved'},
  {'id': 'c2', 'name': 'Travel Diaries', 'members_count': 3400, 'category': 'Travel', 'review_status': 'approved'},
  {'id': 'c3', 'name': 'Desi Kitchen', 'members_count': 8900, 'category': 'Food', 'review_status': 'approved'},
  {'id': 'c4', 'name': 'Fitness Daily', 'members_count': 2100, 'category': 'Fitness', 'review_status': 'approved'},
];

FakeApi _withPlans(FakeApi a) => a..plansList = _plans;

final Map<String, (FakeApi Function(), Widget)> _screens = {
  '1_home': (() => _withPlans(FakeApi(status: statusJson(quota: 16106127360, used: 4294967296), posts: _posts)), const HomeShell()),
  '2_plans': (() => _withPlans(FakeApi(status: statusJson())), const PremiumScreen()),
  '3_cloud': (() => _withPlans(FakeApi(status: statusJson(hasPlan: true, premium: true, quota: 2199023255552, used: 53687091200))), const CloudScreen()),
  '4_channels': (() => _withPlans(FakeApi(status: statusJson(), channelsList: _channels)), const ChannelsScreen()),
  '5_payment': (() => _withPlans(FakeApi()), Scaffold(body: PaymentStatusView(status: 'paid', reference: 'SK20261112GOLD0001', onCheck: () {}, onTryAgain: () {}))),
  '6_profile': (() => _withPlans(FakeApi(guest: true, status: statusJson(guest: true))), const ProfileScreen()),
  '7_welcome': (() => _withPlans(FakeApi()), ConsentScreen(onAgree: () {})),
};

void main() {
  final skip = _fontDir.isEmpty ? 'store screenshots: pass --dart-define=FONT_DIR' : null;
  setUpAll(() async {
    if (skip == null) await _loadFonts();
  });
  for (final e in _screens.entries) {
    testWidgets('store ${e.key}', (t) async {
      await pumpApp(t, e.value.$1(), e.value.$2, width: 360, height: 780);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('raw/${e.key}.png'));
    }, skip: skip != null);
  }
}
