import 'package:flutter/material.dart';

import '../app_state.dart';
import '../services/api.dart';
import '../services/status.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'channels.dart' show ChannelIcon, ChannelPage;
import 'home.dart';
import 'login_sheet.dart';
import 'post.dart';
import 'profile.dart' show ProfileButton;

/// Fixed browsing categories (guide §04). "More" lists every category the server knows.
const exploreCategories = ['All', 'Entertainment', 'Music', 'Learning', 'Technology', 'Education', 'Lifestyle', 'More'];

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});
  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _posts = <Json>[];
  List<Json> _files = const [], _channels = const [];
  String? _cat;
  int _page = 0;
  bool _loading = true, _more = true, _error = false;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) _load();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final api = AppScope.read(context).api;
    setState(() { _posts.clear(); _page = 0; _more = true; _error = false; _loading = true; });
    try {
      final r = await Future.wait([api.recentFiles(), api.channels('discover')]);
      _files = r[0];
      _channels = r[1].take(8).toList();
    } catch (_) {}
    await _load(force: true);
  }

  Future<void> _load({bool force = false}) async {
    if (!force && (_loading || !_more)) return;
    setState(() => _loading = true);
    try {
      final xs = await AppScope.read(context).api.latestPosts(page: _page, category: _cat);
      setState(() { _posts.addAll(xs); _page++; _more = xs.length == Api.pageSize; });
    } catch (_) {
      setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickCategory(String c) async {
    if (c == 'More') {
      final cats = await AppScope.read(context).api.categories();
      if (!mounted) return;
      final picked = await showModalBottomSheet<String>(context: context, builder: (s) => SafeArea(child: ListView(shrinkWrap: true, children: [
        const ListTile(title: Text('All categories', style: TextStyle(fontWeight: FontWeight.w700))),
        for (final x in cats) ListTile(title: Text(x), onTap: () => Navigator.pop(s, x)),
      ])));
      if (picked == null) return;
      c = picked;
    }
    _cat = c == 'All' ? null : c;
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.status;
    final guest = app.api.isGuest;
    final name = (s.displayName ?? app.api.user?.email?.split('@').first ?? '').trim();
    final greeting = switch (DateTime.now().hour) { < 12 => 'Good morning', < 17 => 'Good afternoon', _ => 'Good evening' };

    final header = <Widget>[
      Text(guest || name.isEmpty ? greeting : '$greeting, $name',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: C.text)),
      const SizedBox(height: 4),
      const Text('Your files and channels, in one place.', style: TextStyle(color: C.muted)),
      const SizedBox(height: 16),
      _CloudSummary(status: s, guest: guest),
      if (_files.isNotEmpty) ...[
        SectionHeader('Recent files', onSeeAll: () => HomeShell.of(context)?.go(HomeShellState.cloudTab)),
        Card(child: Column(children: [for (final f in _files) _RecentFile(file: f)])),
      ],
      if (_channels.isNotEmpty) ...[
        SectionHeader('Suggested channels', onSeeAll: () => HomeShell.of(context)?.go(2)),
        SizedBox(height: 132, child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _channels.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (_, i) => _ChannelChip(channel: _channels[i]),
        )),
      ],
      const SectionHeader('Latest posts'),
      SizedBox(height: 40, child: ListView(scrollDirection: Axis.horizontal, children: [
        for (final c in exploreCategories)
          Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(
            label: Text(c == 'More' && _cat != null && !exploreCategories.contains(_cat) ? _cat! : c),
            selected: (c == 'All' && _cat == null) || c == _cat || (c == 'More' && _cat != null && !exploreCategories.contains(_cat)),
            showCheckmark: false,
            onSelected: (_) => _pickCategory(c),
          )),
      ])),
      const SizedBox(height: 12),
    ];

    final List<Widget> feed;
    if (_error && _posts.isEmpty) {
      feed = [Padding(padding: const EdgeInsets.only(top: 24), child: Center(child: Column(children: [
        const Text('Could not load posts.', style: TextStyle(color: C.muted)),
        TextButton(onPressed: _reload, child: const Text('Retry')),
      ])))];
    } else if (_loading && _posts.isEmpty) {
      feed = const [Skeleton(height: 220), Skeleton(height: 220)];
    } else if (_posts.isEmpty) {
      feed = const [Padding(padding: EdgeInsets.symmetric(vertical: 32), child: Column(children: [
        Icon(Icons.movie_outlined, size: 48, color: C.muted),
        SizedBox(height: 8),
        Text('Nothing here yet', style: TextStyle(fontWeight: FontWeight.w600)),
        Text('New posts from channels will show up here.', style: TextStyle(color: C.muted)),
      ]))];
    } else {
      feed = [
        for (final p in _posts) Padding(padding: const EdgeInsets.only(bottom: 12), child: PostCard(post: p)),
        if (_more) const Skeleton(height: 220),
      ];
    }

    return Scaffold(
      appBar: AppBar(
        title: const Logo(size: 30, wordmark: true),
        actions: [
          IconButton(tooltip: 'Search', icon: const Icon(Icons.search), onPressed: () => openSearch(context)),
          const ProfileButton(),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async { await app.refresh(); await _reload(); },
        child: ListView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [...header, ...feed],
        ),
      ),
    );
  }
}

/// Hero card: cloud usage + upload / log-in call to action.
class _CloudSummary extends StatelessWidget {
  const _CloudSummary({required this.status, required this.guest});
  final AppStatus status;
  final bool guest;
  @override
  Widget build(BuildContext context) {
    final hasCloud = !guest && status.quotaBytes > 0;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(gradient: C.heroGradient, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.border)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Your files.\nAlways with you.', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: C.text, height: 1.25)),
          const SizedBox(height: 6),
          Text(hasCloud ? '${formatBytes(status.usedBytes)} of ${formatBytes(status.quotaBytes)} used'
              : 'Store, sync and access your photos, videos and files from anywhere.',
              style: const TextStyle(color: C.muted, fontSize: 13)),
          if (hasCloud) ...[
            const SizedBox(height: 8),
            ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(
                value: (status.usedBytes / status.quotaBytes).clamp(0.0, 1.0), minHeight: 6,
                backgroundColor: Colors.white, color: C.primary)),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () async {
              if (guest && !await requireMember(context, reason: 'Log in to back up your files')) return;
              if (context.mounted) HomeShell.of(context)?.go(HomeShellState.cloudTab);
            },
            icon: Icon(guest ? Icons.login : Icons.cloud_upload_outlined, size: 20),
            label: Text(guest ? 'Get started' : 'Upload files'),
          ),
        ])),
        const SizedBox(width: 12),
        Container(
          width: 84, height: 84,
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Color(0x1F2563EB), blurRadius: 18, offset: Offset(0, 6))]),
          alignment: Alignment.center,
          child: const CloudMark(size: 54),
        ),
      ]),
    );
  }
}

class _RecentFile extends StatelessWidget {
  const _RecentFile({required this.file});
  final Json file;
  @override
  Widget build(BuildContext context) {
    final mime = file['mime'] as String? ?? '';
    final (IconData icon, Color color) = mime.startsWith('image/') ? (Icons.image_outlined, C.primary)
        : mime.startsWith('video/') ? (Icons.movie_outlined, C.accent)
        : mime.startsWith('audio/') ? (Icons.music_note_outlined, C.warningText) : (Icons.description_outlined, C.muted);
    return ListTile(
      leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color)),
      title: Text(file['name'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${formatBytes(file['size_bytes'] as num? ?? 0)} · ${timeAgo(DateTime.tryParse(file['created_at']?.toString() ?? '')?.toLocal())}',
          style: const TextStyle(color: C.muted, fontSize: 12)),
      onTap: () => HomeShell.of(context)?.go(HomeShellState.cloudTab),
    );
  }
}

class _ChannelChip extends StatelessWidget {
  const _ChannelChip({required this.channel});
  final Json channel;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 112,
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChannelPage(channelId: channel['id'] as String))),
            child: Padding(padding: const EdgeInsets.all(10), child: Column(children: [
              ClipOval(child: ChannelIcon(keyName: channel['icon_url'] as String?, size: 52)),
              const SizedBox(height: 8),
              Text(channel['name'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              Text('${compactCount(channel['members_count'] as num? ?? 0)} members', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: C.muted, fontSize: 11)),
            ])),
          ),
        ),
      );
}

class PostCard extends StatelessWidget {
  const PostCard({super.key, required this.post});
  final Json post;
  @override
  Widget build(BuildContext context) {
    final items = (post['post_items'] as List?) ?? const [];
    final thumb = items.isEmpty ? null : (items.first as Map)['thumbnail_key'] as String?;
    final premium = items.any((e) => (e as Map)['is_premium'] == true);
    final channel = post['channels'] as Map?;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PostScreen(postId: post['id'] as String))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AspectRatio(aspectRatio: 16 / 9, child: MediaThumb(keyName: thumb, premium: premium)),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              if (channel != null) ...[ClipOval(child: ChannelIcon(keyName: channel['icon_url'] as String?, size: 34)), const SizedBox(width: 10)],
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(post['title'] as String? ?? '', maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                if (channel != null)
                  Text([channel['name'] ?? '', timeAgo(DateTime.tryParse(post['created_at']?.toString() ?? '')?.toLocal())]
                      .where((x) => '$x'.isNotEmpty).join(' · '),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted, fontSize: 12)),
              ])),
            ]),
          ),
        ]),
      ),
    );
  }
}

class MediaThumb extends StatelessWidget {
  const MediaThumb({super.key, required this.keyName, this.premium = false});
  final String? keyName;
  final bool premium;
  @override
  Widget build(BuildContext context) {
    final api = AppScope.read(context).api;
    return Stack(fit: StackFit.expand, children: [
      Container(color: C.surface2, child: const Icon(Icons.play_circle_outline, size: 48, color: C.muted)),
      if (keyName != null)
        FutureBuilder<String?>(
          future: api.signedUrl('media', keyName),
          builder: (_, s) => s.data == null ? const SizedBox() : Image.network(s.data!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
        ),
      if (premium) const Positioned(top: 8, left: 8, child: PremiumBadge()),
    ]);
  }
}

/// Search posts by title (opened from Explore and Feed).
Future<void> openSearch(BuildContext context) async {
  final q = await showSearch<String?>(context: context, delegate: _Search());
  if (q == null || q.isEmpty || !context.mounted) return;
  await Navigator.push(context, MaterialPageRoute(builder: (_) => SearchResultsScreen(query: q)));
}

class SearchResultsScreen extends StatelessWidget {
  const SearchResultsScreen({super.key, required this.query});
  final String query;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('“$query”', overflow: TextOverflow.ellipsis)),
        body: FutureBuilder<List<Json>>(
          future: AppScope.read(context).api.latestPosts(query: query),
          builder: (_, s) {
            if (s.hasError) return const EmptyState(icon: Icons.cloud_off, title: 'Search failed');
            if (!s.hasData) return const SkeletonList(count: 3);
            if (s.data!.isEmpty) return const EmptyState(icon: Icons.search_off, title: 'No results', message: 'Try a different word.');
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: s.data!.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) => PostCard(post: s.data![i]),
            );
          },
        ),
      );
}

class _Search extends SearchDelegate<String?> {
  _Search() : super(searchFieldLabel: 'Search posts');
  @override
  List<Widget> buildActions(BuildContext context) => [IconButton(tooltip: 'Clear', icon: const Icon(Icons.clear), onPressed: () => query = '')];
  @override
  Widget buildLeading(BuildContext context) => BackButton(onPressed: () => close(context, null));
  @override
  Widget buildResults(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => close(context, query.trim()));
    return const SizedBox();
  }
  @override
  Widget buildSuggestions(BuildContext context) => const SizedBox();
}
