import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skykeep/screens/channels.dart';
import 'package:skykeep/screens/checkout.dart';
import 'package:skykeep/screens/cloud.dart';
import 'package:skykeep/screens/explore.dart';
import 'package:skykeep/screens/home.dart';
import 'package:skykeep/screens/premium.dart';
import 'package:skykeep/screens/profile.dart';

import 'fakes.dart';

final _posts = [
  for (var i = 0; i < 3; i++)
    {'id': 'p$i', 'title': 'Weekend trip to the hills, part ${i + 1}', 'channels': {'name': 'Travel Diaries'},
      'post_items': [{'thumbnail_key': null, 'is_premium': i == 1}]},
];
final _channels = [
  {'id': 'c1', 'name': 'SkyKeep Tips', 'members_count': 1200, 'category': 'Tech', 'review_status': 'approved'},
  {'id': 'c2', 'name': 'Travel Diaries', 'members_count': 340, 'category': 'Travel', 'review_status': 'approved'},
];

Map<String, (FakeApi Function(), Widget)> screens() => {
      'explore': (() => FakeApi(status: statusJson(), posts: _posts), const ExploreScreen()),
      'channels': (() => FakeApi(status: statusJson(), channelsList: _channels), const ChannelsScreen()),
      'cloud': (() => FakeApi(status: statusJson(hasPlan: true, premium: true, quota: 2199023255552, used: 5368709120)), const CloudScreen()),
      'profile_guest': (() => FakeApi(guest: true, status: statusJson(guest: true)), const ProfileScreen()),
      'profile_member': (() => FakeApi(status: statusJson(hasPlan: true, premium: true, quota: 2199023255552)), const ProfileScreen()),
      'premium_web': (() => FakeApi(status: statusJson()), const PremiumScreen()),
      'free_mode': (() => FakeApi(status: statusJson(source: 'organic', freeMode: true, plansVisible: false, quota: 16106127360)), const PremiumScreen()),
      'plans_hidden': (() => FakeApi(status: statusJson(plansVisible: false)), const PremiumScreen()),
      'upi_success': (FakeApi.new, Scaffold(body: PaymentStatusView(status: 'paid', reference: 'SK20261109ABCDEF12', onCheck: () {}, onTryAgain: () {}))),
      'upi_review': (FakeApi.new, Scaffold(body: PaymentStatusView(status: 'review', reference: 'SK20261109ABCDEF12', onCheck: () {}, onTryAgain: () {}))),
      'upi_failed': (FakeApi.new, Scaffold(body: PaymentStatusView(status: 'failed', reference: 'SK20261109ABCDEF12', onCheck: () {}, onTryAgain: () {}))),
      'home': (() => FakeApi(status: statusJson(), posts: _posts), const HomeShell()),
    };

void main() {
  for (final width in [360.0, 430.0]) {
    for (final e in screens().entries) {
      testWidgets('golden ${e.key} @${width.toInt()}', (t) async {
        await pumpApp(t, e.value.$1(), e.value.$2, width: width, height: 800);
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/${e.key}_${width.toInt()}.png'));
      }, tags: ['golden']);
    }
  }

  // 360 px wide with 1.6× text must not overflow (overflow throws in tests).
  for (final e in screens().entries) {
    testWidgets('no overflow at 1.6× text: ${e.key}', (t) async {
      await pumpApp(t, e.value.$1(), e.value.$2, width: 360, height: 800, textScale: 1.6);
      expect(t.takeException(), isNull);
    });
  }
}
