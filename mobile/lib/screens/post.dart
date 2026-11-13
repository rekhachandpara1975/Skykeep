import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../config.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/pro_player.dart';
import 'explore.dart';
import 'home.dart' show HomeShellState;
import 'login_sheet.dart';
import 'premium.dart';

const reportReasons = ['Sexual/nude', 'Violence', 'Hate/harassment', 'Copyright', 'Spam/scam', 'Other'];

class PostScreen extends StatefulWidget {
  const PostScreen({super.key, required this.postId, this.queue = const []});
  final String postId;

  /// Posts in the order they were listed: powers the player's previous / next buttons.
  final List<String> queue;
  @override
  State<PostScreen> createState() => _PostScreenState();
}

class _PostScreenState extends State<PostScreen> {
  Json? _post;
  List<Json> _more = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final api = AppScope.read(context).api;
    try {
      _post = await api.post(widget.postId);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
    try {
      // Suggest any other video (same channel included) — excluding only this post, so a single-channel
      // app still shows "More to watch".
      final more = await api.suggestedPosts(widget.postId);
      if (mounted) setState(() => _more = more);
    } catch (_) {}
  }

  int get _at => widget.queue.indexOf(widget.postId);

  // The next / previous buttons play through the list the post was opened from; when it runs out,
  // "next" continues into the suggested videos so the user can keep watching.
  String? get _nextId {
    if (_at >= 0 && _at < widget.queue.length - 1) return widget.queue[_at + 1];
    return _more.isNotEmpty ? _more.first['id'] as String? : null;
  }

  String? get _prevId => _at > 0 ? widget.queue[_at - 1] : null;

  void _open(String id, List<String> queue) =>
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => PostScreen(postId: id, queue: queue)));

  void _next() {
    final id = _nextId;
    if (id == null) return;
    if (_at >= 0 && _at < widget.queue.length - 1) {
      _open(id, widget.queue);
    } else {
      _open(id, [for (final p in _more) p['id'] as String]); // keep playing through the suggestions
    }
  }

  void _previous() {
    final id = _prevId;
    if (id != null) _open(id, widget.queue);
  }

  Future<void> _report() async {
    if (!await requireMember(context, reason: 'Log in to report')) return;
    if (!mounted) return;
    final reason = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: C.surface,
      builder: (c) => SafeArea(child: ListView(shrinkWrap: true, children: [
        const ListTile(title: Text('Why are you reporting this?')),
        for (final r in reportReasons) ListTile(title: Text(r), onTap: () => Navigator.pop(c, r)),
      ])),
    );
    if (reason == null || !mounted) return;
    try {
      await AppScope.read(context).api.report('post', widget.postId, reason, null);
      if (mounted) toast(context, 'Thanks — our team will review it.');
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _block() async {
    final ch = _post?['channels'] as Map?;
    if (ch == null || !await requireMember(context, reason: 'Log in to block channels')) return;
    if (!mounted) return;
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text('Block ${ch['name']}?'), content: const Text('You will no longer see posts from this channel.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Block'))]));
    if (ok != true || !mounted) return;
    try {
      await AppScope.read(context).api.blockChannel(ch['id'] as String);
      if (mounted) { toast(context, 'Channel blocked'); Navigator.pop(context); }
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = [...((_post?['post_items'] as List?) ?? const [])]..sort((a, b) => (((a as Map)['position'] as num?) ?? 0).compareTo(((b as Map)['position'] as num?) ?? 0));
    return Scaffold(
      appBar: AppBar(
        title: Text(_post?['title'] as String? ?? ''),
        actions: [
          IconButton(tooltip: 'Share', icon: const Icon(Icons.share),
              onPressed: () => SharePlus.instance.share(ShareParams(text: '${_post?['title'] ?? Config.appName} ${Config.websiteUrl}/p/${widget.postId}'))),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) => v == 'report' ? _report() : _block(),
            itemBuilder: (_) => const [PopupMenuItem(value: 'report', child: Text('Report')), PopupMenuItem(value: 'block', child: Text('Block channel'))],
          ),
        ],
      ),
      body: _loading
          ? const SkeletonList(count: 3)
          : _post == null
              ? const EmptyState(icon: Icons.lock_outline, title: 'This post is not available')
              : ListView(padding: const EdgeInsets.all(16), children: [
                  Text((_post!['channels'] as Map?)?['name'] as String? ?? '', style: const TextStyle(color: C.muted)),
                  if ((_post!['description'] as String?)?.isNotEmpty == true)
                    Padding(padding: const EdgeInsets.only(top: 8), child: Text(_post!['description'] as String)),
                  const SizedBox(height: 16),
                  for (final it in items) Padding(padding: const EdgeInsets.only(bottom: 16), child: MediaItem(
                      item: Json.from(it as Map), title: _post!['title'] as String?,
                      onNext: _nextId != null ? _next : null,
                      onPrevious: _prevId != null ? _previous : null)),
                  if (_more.isNotEmpty) _MoreToWatch(posts: _more),
                ]),
    );
  }
}

/// "More to watch": public videos from other channels, shown under the player for every viewer.
class _MoreToWatch extends StatelessWidget {
  const _MoreToWatch({required this.posts});
  final List<Json> posts;
  @override
  Widget build(BuildContext context) {
    final queue = [for (final p in posts) p['id'] as String];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('More to watch', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 12),
        SizedBox(height: 190, child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: posts.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (context, i) {
            final p = posts[i];
            final its = (p['post_items'] as List?) ?? const [];
            final thumb = its.isEmpty ? null : (its.first as Map)['thumbnail_key'] as String?;
            final premium = its.any((e) => (e as Map)['is_premium'] == true);
            final channel = (p['channels'] as Map?)?['name'] as String?;
            return SizedBox(width: 130, child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(
                  builder: (_) => PostScreen(postId: p['id'] as String, queue: queue))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(16),
                    child: AspectRatio(aspectRatio: .72, child: MediaThumb(keyName: thumb, premium: premium)))),
                const SizedBox(height: 6),
                Text(p['title'] as String? ?? '', maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, height: 1.15)),
                if (channel != null)
                  Text(channel, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted, fontSize: 11)),
              ]),
            ));
          },
        )),
      ]),
    );
  }
}

/// One media item: asks the server what to play (full / trailer / locked).
class MediaItem extends StatefulWidget {
  const MediaItem({super.key, required this.item, this.title, this.onNext, this.onPrevious});
  final Json item;
  final String? title;
  final VoidCallback? onNext, onPrevious;
  @override
  State<MediaItem> createState() => _MediaItemState();
}

class _MediaItemState extends State<MediaItem> {
  Json? _play;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try { _play = await AppScope.read(context).api.playable(widget.item['id'] as String); } catch (_) {}
      if (mounted) setState(() => _loaded = true);
    });
  }

  Future<void> _download() async {
    final app = AppScope.read(context);
    if (!app.status.isPremium) {
      toast(context, 'Downloads are for Premium members');
      if (Config.sellsPlans) { Navigator.of(context).popUntil((r) => r.isFirst); HomeShellState.current?.go(HomeShellState.premiumTab); }
      return;
    }
    final url = await app.api.signedUrl('media', _play?['key'] as String?, download: true);
    if (!mounted) return;
    if (url == null) { toast(context, 'Could not start the download. Please try again.'); return; }
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).status;
    final kind = _play?['kind'] as String?;
    final isVideo = (widget.item['mime'] as String? ?? '').startsWith('video/') || widget.item['duration_s'] != null;
    if (!_loaded) return const Skeleton(height: 200);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (kind == 'locked')
        _Locked(plansVisible: s.plansVisible && Config.sellsPlans)
      else if (kind != null && isVideo)
        ProPlayer(
          itemId: widget.item['id'] as String, storageKey: _play!['key'] as String, title: widget.title,
          trailerKey: kind == 'full' ? _play!['trailer_key'] as String? : null, // watch the trailer first, then the full video
          trailerOnly: kind == 'trailer', onNext: widget.onNext, onPrevious: widget.onPrevious,
          onUpgrade: s.plansVisible && Config.sellsPlans ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PremiumScreen())) : null,
        )
      else if (kind != null)
        ClipRRect(borderRadius: BorderRadius.circular(12),
            child: AspectRatio(aspectRatio: 16 / 9, child: MediaThumb(keyName: _play!['key'] as String))),
      if (kind == 'trailer')
        Padding(padding: const EdgeInsets.only(top: 8), child: Text(
            s.plansVisible && Config.sellsPlans ? 'Trailer · Get Premium to watch the full video' : 'Trailer · Full video for Premium members',
            style: const TextStyle(color: C.goldText, fontWeight: FontWeight.w600))),
      if (kind == 'full') // the server only returns 'full' to people allowed to have the file
        Align(alignment: Alignment.centerLeft,
            child: TextButton.icon(onPressed: _download, icon: const Icon(Icons.download), label: const Text('Download'))),
    ]);
  }
}

class _Locked extends StatelessWidget {
  const _Locked({required this.plansVisible});
  final bool plansVisible;
  @override
  Widget build(BuildContext context) => Container(
        height: 200,
        decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.lock, color: C.gold, size: 36),
          const SizedBox(height: 8),
          const Text('For Premium members', style: TextStyle(fontWeight: FontWeight.w600)),
          if (plansVisible)
            TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PremiumScreen())),
                child: const Text('Get Premium')),
        ]),
      );
}
