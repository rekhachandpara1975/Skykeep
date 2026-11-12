import 'package:flutter/material.dart';

import '../theme.dart';
import 'channels.dart';
import 'cloud.dart';
import 'explore.dart';
import 'feed.dart';
import 'profile.dart';

/// Bottom navigation: Explore · Feed · Channels · Cloud · Profile.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.initialTab = 0});
  final int initialTab;
  @override
  State<HomeShell> createState() => HomeShellState();

  /// Lets screens switch tabs (e.g. Explore's "Get started" → Cloud).
  static HomeShellState? of(BuildContext context) => context.findAncestorStateOfType<HomeShellState>();
}

class HomeShellState extends State<HomeShell> {
  late int _tab = widget.initialTab;
  static const _pages = [ExploreScreen(), FeedScreen(), ChannelsScreen(), CloudScreen(), ProfileScreen()];
  static const cloudTab = 3;

  void go(int tab) => setState(() => _tab = tab);

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: _tab, children: _pages),
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.border))),
          child: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: go,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Explore'),
              NavigationDestination(icon: Icon(Icons.dynamic_feed_outlined), selectedIcon: Icon(Icons.dynamic_feed), label: 'Feed'),
              NavigationDestination(icon: Icon(Icons.hub_outlined), selectedIcon: Icon(Icons.hub), label: 'Channels'),
              NavigationDestination(icon: Icon(Icons.cloud_outlined), selectedIcon: Icon(Icons.cloud), label: 'Cloud'),
              NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
            ],
          ),
        ),
      );
}
