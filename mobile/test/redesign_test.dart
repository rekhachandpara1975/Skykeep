import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skykeep/screens/channels.dart';
import 'package:skykeep/screens/cloud.dart';
import 'package:skykeep/screens/explore.dart';
import 'package:skykeep/screens/feed.dart';
import 'package:skykeep/screens/home.dart';
import 'package:skykeep/services/status.dart';

import 'fakes.dart';

final _posts = [
  {'id': 'p1', 'title': 'Sunrise over the hills', 'created_at': DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
    'channels': {'id': 'c1', 'name': 'Nature Vibes', 'members_count': 245000}, 'post_items': [{'thumbnail_key': null, 'is_premium': false}]},
];

void main() {
  testWidgets('five tabs: Explore, Feed, Channels, Cloud, Profile', (t) async {
    await pumpApp(t, FakeApi(posts: _posts), const HomeShell());
    for (final l in ['Explore', 'Feed', 'Channels', 'Cloud', 'Profile']) {
      expect(find.descendant(of: find.byType(NavigationBar), matching: find.text(l)), findsOneWidget, reason: l);
    }
    await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Feed')));
    await t.pumpAndSettle();
    expect(find.text('For You'), findsOneWidget);
  });

  testWidgets('Explore: greeting, cloud summary, categories, recent files, posts', (t) async {
    final api = FakeApi(status: statusJson(quota: 16106127360, used: 1073741824), posts: _posts)
      ..recentFilesList = [{'id': 'f1', 'name': 'Vacation.jpg', 'mime': 'image/jpeg', 'size_bytes': 2400000,
        'created_at': DateTime.now().toIso8601String()}];
    await pumpApp(t, api, const ExploreScreen());
    expect(find.textContaining('Asha'), findsOneWidget);
    expect(find.text('Upload files'), findsOneWidget);
    expect(find.text('Vacation.jpg'), findsOneWidget);
    expect(exploreCategories, ['All', 'Entertainment', 'Music', 'Learning', 'Technology', 'Education', 'Lifestyle', 'More']);
    expect(find.widgetWithText(ChoiceChip, 'All'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Entertainment'), findsOneWidget);
    expect(find.text('Sunrise over the hills'), findsOneWidget);
  });

  testWidgets('Explore as guest: Get started, no recent files', (t) async {
    await pumpApp(t, FakeApi(guest: true, status: statusJson(guest: true), posts: _posts), const ExploreScreen());
    expect(find.text('Get started'), findsOneWidget);
    expect(find.text('Recent files'), findsNothing);
  });

  testWidgets('Feed: Following shows joined channels, guest gets a log-in prompt', (t) async {
    await pumpApp(t, FakeApi(posts: _posts), const FeedScreen());
    await t.tap(find.text('Following'));
    await t.pumpAndSettle();
    expect(find.text('Nature Vibes'), findsOneWidget);
    expect(find.text('2 hours ago'), findsOneWidget);
    await pumpApp(t, FakeApi(guest: true, status: statusJson(guest: true), posts: _posts), const FeedScreen());
    await t.tap(find.text('Following'));
    await t.pumpAndSettle();
    expect(find.text('Log in to follow channels'), findsOneWidget);
  });

  testWidgets('Channels: Discover list has Join buttons and a create button', (t) async {
    await pumpApp(t, FakeApi(channelsList: const [{'id': 'c1', 'name': 'Tech World', 'members_count': 245000, 'category': 'Technology', 'review_status': 'approved'}]),
        const ChannelsScreen());
    expect(find.text('Tech World'), findsWidgets);
    expect(find.text('245K members · Technology'), findsWidgets);
    expect(find.text('Join'), findsWidgets);
    expect(find.text('Create your channel'), findsOneWidget);
  });

  testWidgets('Cloud: storage ring with percentage', (t) async {
    await pumpApp(t, FakeApi(status: statusJson(quota: 16106127360, used: 1288490189)), const CloudScreen());
    expect(find.text('8%'), findsOneWidget);
    expect(find.text('Storage'), findsOneWidget);
  });

  test('timeAgo and compactCount', () {
    final now = DateTime(2026, 11, 12, 12);
    expect(timeAgo(now.subtract(const Duration(minutes: 5)), now: now), '5 min ago');
    expect(timeAgo(now.subtract(const Duration(hours: 1)), now: now), '1 hour ago');
    expect(timeAgo(now.subtract(const Duration(days: 3)), now: now), '3 days ago');
    expect(compactCount(950), '950');
    expect(compactCount(1200), '1.2K');
    expect(compactCount(245000), '245K');
    expect(compactCount(3400000), '3.4M');
  });
}
