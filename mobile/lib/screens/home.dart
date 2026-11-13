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
  static const premiumTab = 4;

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
        bottomNavigationBar: _NavBar(selected: _tab, onSelected: go),
      );
}

/// Bottom bar: the selected tab is a red pill holding its icon and label.
class _NavBar extends StatelessWidget {
  const _NavBar({required this.selected, required this.onSelected});
  final int selected;
  final ValueChanged<int> onSelected;
  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, 'Explore'),
    (Icons.dynamic_feed_outlined, Icons.dynamic_feed, 'Feed'),
    (Icons.hub_outlined, Icons.hub, 'Channels'),
    (Icons.cloud_outlined, Icons.cloud, 'Cloud'),
    (Icons.workspace_premium_outlined, Icons.workspace_premium, 'Premium'),
  ];

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('nav-bar'),
        decoration: const BoxDecoration(color: C.surface, border: Border(top: BorderSide(color: C.border))),
        child: SafeArea(top: false, child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Row(children: [
            for (final (i, it) in _items.indexed)
              Expanded(flex: i == selected ? 5 : 4, child: Semantics(
                selected: i == selected, button: true, label: it.$3,
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: () => onSelected(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(color: i == selected ? C.primary : Colors.transparent, borderRadius: BorderRadius.circular(22)),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(i == selected ? it.$2 : it.$1, size: 26, color: i == selected ? Colors.white : C.muted),
                      const SizedBox(height: 2),
                      FittedBox(fit: BoxFit.scaleDown, child: Text(it.$3, maxLines: 1,
                          style: TextStyle(fontSize: 12, fontWeight: i == selected ? FontWeight.w700 : FontWeight.w500, color: i == selected ? Colors.white : C.muted))),
                    ]),
                  ),
                ),
              )),
          ]),
        )),
      );
}
