import 'package:flutter/material.dart';

import '../app_state.dart';
import '../config.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'post.dart';
import 'premium.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});
  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _posts = <Json>[];
  List<String> _cats = const [];
  String? _cat, _query;
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

  Future<void> _reload() async {
    final api = AppScope.read(context).api;
    setState(() { _posts.clear(); _page = 0; _more = true; _error = false; _loading = true; });
    try { _cats = await api.categories(); } catch (_) {}
    await _load(force: true);
  }

  Future<void> _load({bool force = false}) async {
    if (!force && (_loading || !_more)) return;
    setState(() => _loading = true);
    try {
      final xs = await AppScope.read(context).api.latestPosts(page: _page, category: _cat, query: _query);
      setState(() { _posts.addAll(xs); _page++; _more = xs.length == Api.pageSize; });
    } catch (_) {
      setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _search() async {
    final q = await showSearch<String?>(context: context, delegate: _Search(_query));
    if (q == null) return;
    _query = q;
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).status;
    final showCrown = s.plansVisible && !Config.playStore;
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [Logo(size: 28), SizedBox(width: 10), Flexible(child: Text(Config.appName, overflow: TextOverflow.ellipsis))]),
        actions: [
          IconButton(tooltip: 'Search', icon: const Icon(Icons.search), onPressed: _search),
          if (showCrown)
            IconButton(tooltip: 'Premium', icon: const Icon(Icons.workspace_premium, color: C.gold),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PremiumScreen()))),
        ],
      ),
      body: Column(children: [
        SizedBox(
          height: 52,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children: [
            for (final c in [null, ..._cats])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: Text(c ?? 'All'), selected: _cat == c, onSelected: (_) { _cat = c; _reload(); }),
              ),
          ]),
        ),
        if (_query != null && _query!.isNotEmpty)
          ListTile(dense: true, title: Text('Results for “$_query”'),
              trailing: IconButton(tooltip: 'Clear search', icon: const Icon(Icons.close), onPressed: () { _query = null; _reload(); })),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _reload,
            child: _error && _posts.isEmpty
                ? ErrorRetry(onRetry: _reload)
                : _loading && _posts.isEmpty
                    ? const SkeletonList()
                    : _posts.isEmpty
                        ? const EmptyState(icon: Icons.movie_outlined, title: 'Nothing here yet', message: 'New posts from channels will show up here.')
                        : ListView.separated(
                            controller: _scroll,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            itemCount: _posts.length + (_more ? 1 : 0),
                            separatorBuilder: (_, _) => const SizedBox(height: 12),
                            itemBuilder: (_, i) => i == _posts.length ? const Skeleton() : PostCard(post: _posts[i]),
                          ),
          ),
        ),
      ]),
    );
  }
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
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(post['title'] as String? ?? '', maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              if (channel != null) Text(channel['name'] as String? ?? '', style: const TextStyle(color: C.muted)),
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

class _Search extends SearchDelegate<String?> {
  _Search(String? q) { query = q ?? ''; }
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
