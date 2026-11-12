import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../app_state.dart';
import '../config.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'explore.dart';
import 'login_sheet.dart';
import 'premium.dart';

const reportReasons = ['Sexual/nude', 'Violence', 'Hate/harassment', 'Copyright', 'Spam/scam', 'Other'];

class PostScreen extends StatefulWidget {
  const PostScreen({super.key, required this.postId});
  final String postId;
  @override
  State<PostScreen> createState() => _PostScreenState();
}

class _PostScreenState extends State<PostScreen> {
  Json? _post;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      _post = await AppScope.read(context).api.post(widget.postId);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
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
    await AppScope.read(context).api.report('post', widget.postId, reason, null);
    if (mounted) toast(context, 'Thanks — our team will review it.');
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
    await AppScope.read(context).api.blockChannel(ch['id'] as String);
    if (mounted) { toast(context, 'Channel blocked'); Navigator.pop(context); }
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
                  for (final it in items) Padding(padding: const EdgeInsets.only(bottom: 16), child: MediaItem(item: Json.from(it as Map))),
                ]),
    );
  }
}

/// One media item: asks the server what to play (full / trailer / locked).
class MediaItem extends StatefulWidget {
  const MediaItem({super.key, required this.item});
  final Json item;
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
        Player(itemId: widget.item['id'] as String, storageKey: _play!['key'] as String, trailer: kind == 'trailer')
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

/// Video with signed-URL refresh and resume position.
class Player extends StatefulWidget {
  const Player({super.key, required this.itemId, required this.storageKey, this.trailer = false});
  final String itemId, storageKey;
  final bool trailer;
  @override
  State<Player> createState() => _PlayerState();
}

class _PlayerState extends State<Player> {
  VideoPlayerController? _c;
  Timer? _save;
  bool _failed = false;

  String get _posKey => 'pos_${widget.storageKey}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open({bool refresh = false}) async {
    final app = AppScope.read(context);
    if (refresh) app.api.forgetSigned('media', widget.storageKey);
    final url = await app.api.signedUrl('media', widget.storageKey);
    if (url == null) return setState(() => _failed = true);
    final resumeAt = Duration(milliseconds: _c?.value.position.inMilliseconds ?? app.prefs.getInt(_posKey) ?? 0);
    final old = _c;
    final c = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await c.initialize();
      await c.seekTo(resumeAt);
      c.addListener(() {
        // signed URL expired mid-stream → refresh and continue
        if (c.value.hasError && mounted) _open(refresh: true);
      });
      setState(() { _c = c; _failed = false; });
      await old?.dispose();
      _save ??= Timer.periodic(const Duration(seconds: 5), (_) {
        final p = _c?.value.position;
        if (p != null) app.prefs.setInt(_posKey, p.inMilliseconds);
      });
    } catch (_) {
      await c.dispose();
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _save?.cancel();
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (_failed) {
      return AspectRatio(aspectRatio: 16 / 9, child: Center(child: OutlinedButton(onPressed: () => _open(refresh: true), child: const Text('Retry video'))));
    }
    if (c == null || !c.value.isInitialized) {
      return const AspectRatio(aspectRatio: 16 / 9, child: Center(child: CircularProgressIndicator()));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
        child: Stack(alignment: Alignment.bottomCenter, children: [
          VideoPlayer(c),
          GestureDetector(onTap: () => setState(() => c.value.isPlaying ? c.pause() : c.play())),
          if (!c.value.isPlaying)
            Center(child: Semantics(button: true, label: 'Play', child: IconButton.filled(iconSize: 40,
                onPressed: () => setState(c.play), icon: const Icon(Icons.play_arrow)))),
          VideoProgressIndicator(c, allowScrubbing: true, colors: const VideoProgressColors(playedColor: C.primary)),
        ]),
      ),
    );
  }
}
