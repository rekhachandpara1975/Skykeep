import 'package:flutter/material.dart';

import '../theme.dart';
import 'channels.dart';
import 'cloud.dart';
import 'explore.dart';
import 'feed.dart';
import 'premium.dart';

/// Bottom navigation: Explore · Feed · Channels · Cloud · Premium. Profile opens from the avatar at the top right.
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
  static const _pages = [ExploreScreen(), FeedScreen(), ChannelsScreen(), CloudScreen(), PremiumScreen()];
  static const cloudTab = 3;

  /// The live shell, so pushed pages (Profile → "My cloud") can switch tabs.
  static HomeShellState? current;

  @override
  void initState() {
    super.initState();
    current = this;
  }

  @override
  void dispose() {
    if (current == this) current = null;
    super.dispose();
  }

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
              NavigationDestination(icon: Icon(Icons.workspace_premium_outlined), selectedIcon: Icon(Icons.workspace_premium), label: 'Premium'),
            ],
          ),
        ),
      );
}
