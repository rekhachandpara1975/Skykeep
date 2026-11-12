import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../config.dart';
import '../services/api.dart';
import '../services/status.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'explore.dart';
import 'login_sheet.dart';
import 'premium.dart';

class ChannelsScreen extends StatefulWidget {
  const ChannelsScreen({super.key});
  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen> {
  int _tab = 0;
  static const _tabs = ['discover', 'joined', 'mine'];

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Channels')),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: PillTabs(labels: const ['Discover', 'Joined', 'Mine'], index: _tab, onChanged: (i) => setState(() => _tab = i)),
          ),
          Expanded(child: IndexedStack(index: _tab, children: [for (final t in _tabs) ChannelList(tab: t)])),
          SafeArea(top: false, child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SizedBox(width: double.infinity, child: GradientButton(
                label: 'Create your channel', icon: Icons.add, onPressed: () => openChannelForm(context))),
          )),
        ]),
      );
}

Future<void> openChannelForm(BuildContext context, {Json? channel}) async {
  if (!await requireMember(context, reason: 'Log in to create a channel')) return;
  if (!context.mounted || !await requireConsent(context)) return;
  if (!context.mounted) return;
  await Navigator.push(context, MaterialPageRoute(builder: (_) => ChannelForm(channel: channel)));
}

class ChannelList extends StatefulWidget {
  const ChannelList({super.key, required this.tab});
  final String tab;
  @override
  State<ChannelList> createState() => _ChannelListState();
}

class _ChannelListState extends State<ChannelList> {
  Future<List<Json>>? _f;
  Set<String> _joined = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _f ??= _load();
  }

  Future<List<Json>> _load() async {
    final api = AppScope.read(context).api;
    if (widget.tab != 'discover' && api.isGuest) return const [];
    if (widget.tab == 'discover' && !api.isGuest) {
      try {
        _joined = {for (final c in await api.channels('joined')) c['id'] as String};
      } catch (_) {}
    }
    return api.channels(widget.tab);
  }

  Future<void> _refresh() async { setState(() => _f = _load()); await _f; }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<Json>>(
        future: _f,
        builder: (_, s) {
          if (s.hasError) return ErrorRetry(onRetry: _refresh);
          if (!s.hasData) return const SkeletonList();
          if (s.data!.isEmpty) {
            return EmptyState(icon: Icons.groups_outlined,
                title: widget.tab == 'mine' ? 'You have no channels yet' : widget.tab == 'joined' ? 'You have not joined any channels' : 'No channels yet');
          }
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            itemCount: s.data!.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) => ChannelTile(channel: s.data![i], onChanged: _refresh,
                joined: widget.tab == 'discover' ? _joined.contains(s.data![i]['id']) : null),
          );
        },
      ),
    );
  }
}

class ChannelIcon extends StatelessWidget {
  const ChannelIcon({super.key, required this.keyName, this.size = 48});
  final String? keyName;
  final double size;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(size / 4),
        child: SizedBox(width: size, height: size, child: Container(
          color: C.surface2,
          child: keyName == null ? const Icon(Icons.tag, color: C.muted) : FutureBuilder<String?>(
            future: AppScope.read(context).api.signedUrl('channel-icons', keyName),
            builder: (_, s) => s.data == null ? const SizedBox() : Image.network(s.data!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
          ),
        )),
      );
}

class ChannelTile extends StatefulWidget {
  const ChannelTile({super.key, required this.channel, this.onChanged, this.joined});
  final Json channel;
  final VoidCallback? onChanged;
  /// null = no Join button (Joined / Mine lists)
  final bool? joined;
  @override
  State<ChannelTile> createState() => _ChannelTileState();
}

class _ChannelTileState extends State<ChannelTile> {
  late bool? _joined = widget.joined;
  bool _busy = false;

  @override
  void didUpdateWidget(ChannelTile old) {
    super.didUpdateWidget(old);
    if (old.joined != widget.joined) _joined = widget.joined;
  }

  Future<void> _toggle() async {
    final api = AppScope.read(context).api;
    if (!await requireMember(context, reason: 'Log in to join channels')) return;
    setState(() => _busy = true);
    try {
      final id = widget.channel['id'] as String;
      if (_joined == true) {
        await api.leave(id);
      } else {
        await api.join(id);
      }
      if (mounted) setState(() => _joined = !(_joined ?? false));
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final channel = widget.channel;
    final pending = channel['review_status'] == 'pending';
    final rejected = channel['review_status'] == 'rejected';
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => ChannelPage(channelId: channel['id'] as String)));
          widget.onChanged?.call();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(children: [
            ClipOval(child: ChannelIcon(keyName: channel['icon_url'] as String?, size: 48)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(channel['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 2),
              Text(pending ? 'Waiting for approval' : rejected ? 'Not approved'
                  : '${compactCount(channel['members_count'] as num? ?? 0)} members${channel['category'] == null ? '' : ' · ${channel['category']}'}',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: pending ? C.warningText : rejected ? C.dangerText : C.muted)),
            ])),
            if (_joined != null) ...[
              const SizedBox(width: 8),
              _joined!
                  ? OutlinedButton(onPressed: _busy ? null : _toggle,
                      style: OutlinedButton.styleFrom(minimumSize: const Size(80, 40)), child: const Text('Joined'))
                  : FilledButton(onPressed: _busy ? null : _toggle,
                      style: FilledButton.styleFrom(minimumSize: const Size(80, 40), backgroundColor: C.primarySoft, foregroundColor: C.primary),
                      child: const Text('Join')),
            ],
          ]),
        ),
      ),
    );
  }
}

class ChannelPage extends StatefulWidget {
  const ChannelPage({super.key, required this.channelId});
  final String channelId;
  @override
  State<ChannelPage> createState() => _ChannelPageState();
}

class _ChannelPageState extends State<ChannelPage> {
  Json? _ch;
  List<Json> _posts = const [];
  bool _member = false, _loading = true, _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final api = AppScope.read(context).api;
    try {
      _ch = await api.channel(widget.channelId);
      _posts = await api.channelPosts(widget.channelId);
      _member = !api.isGuest && await api.isMember(widget.channelId);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggle() async {
    if (!await requireMember(context, reason: 'Log in to join channels')) return;
    if (!mounted) return;
    final api = AppScope.read(context).api;
    setState(() => _busy = true);
    try {
      _member ? await api.leave(widget.channelId) : await api.join(widget.channelId);
      await _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _upload() async {
    if (!await requireConsent(context)) return;
    if (!mounted) return;
    final file = await FilePicker.pickFile(type: FileType.media);
    if (file == null || !mounted) return;
    final title = await _ask(context, 'Post title', file.name.split('.').first);
    if (title == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await AppScope.read(context).api.uploadPost(channelId: widget.channelId, title: title, fileName: file.name, bytes: await file.readAsBytes(),
          mime: _mime(file.extension));
      if (mounted) toast(context, 'Posted');
      await _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final ch = _ch;
    final mine = ch != null && ch['created_by'] == app.api.user?.id;
    final approved = ch?['review_status'] == 'approved';
    return Scaffold(
      appBar: AppBar(title: Text(ch?['name'] as String? ?? ''), actions: [
        if (app.status.plansVisible && !Config.playStore)
          IconButton(tooltip: 'Premium', icon: const Icon(Icons.workspace_premium, color: C.gold),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PremiumScreen()))),
        if (mine) IconButton(tooltip: 'Edit channel', icon: const Icon(Icons.edit), onPressed: () async { await openChannelForm(context, channel: ch); _load(); }),
      ]),
      floatingActionButton: mine && approved
          ? FloatingActionButton.extended(onPressed: _busy ? null : _upload, icon: const Icon(Icons.upload), label: const Text('Upload'))
          : null,
      body: _loading
          ? const SkeletonList(count: 4)
          : ch == null
              ? const EmptyState(icon: Icons.lock_outline, title: 'Channel not available')
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    Row(children: [
                      ChannelIcon(keyName: ch['icon_url'] as String?, size: 64),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(ch['name'] as String, style: Theme.of(context).textTheme.titleLarge),
                        Text('${ch['members_count'] ?? 0} members', style: const TextStyle(color: C.muted)),
                      ])),
                    ]),
                    if (ch['review_status'] == 'pending')
                      const Padding(padding: EdgeInsets.only(top: 12), child: Card(child: ListTile(
                          leading: Icon(Icons.hourglass_top, color: C.warning), title: Text('Waiting for approval'),
                          subtitle: Text('Our team reviews new channels. You can upload once it is approved.')))),
                    if ((ch['description'] as String?)?.isNotEmpty == true)
                      Padding(padding: const EdgeInsets.only(top: 12), child: Text(ch['description'] as String)),
                    const SizedBox(height: 12),
                    if (!mine && approved)
                      _member
                          ? OutlinedButton(onPressed: _busy ? null : _toggle, child: const Text('Leave channel'))
                          : GradientButton(label: 'Join channel', onPressed: _busy ? null : _toggle),
                    const SizedBox(height: 16),
                    if (_posts.isEmpty) const Text('No posts yet.', style: TextStyle(color: C.muted)),
                    for (final p in _posts) Padding(padding: const EdgeInsets.only(bottom: 12), child: PostCard(post: {...p, 'channels': null})),
                  ]),
                ),
    );
  }
}

String? _mime(String? ext) => switch ((ext ?? '').toLowerCase()) {
      'mp4' => 'video/mp4', 'mov' => 'video/quicktime', 'mkv' => 'video/x-matroska', 'webm' => 'video/webm',
      'jpg' || 'jpeg' => 'image/jpeg', 'png' => 'image/png', 'gif' => 'image/gif', 'webp' => 'image/webp',
      'pdf' => 'application/pdf', _ => null,
    };
String? mimeFor(String? ext) => _mime(ext);

Future<String?> _ask(BuildContext context, String title, String initial) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(context: context, builder: (d) => AlertDialog(
    title: Text(title), content: TextField(controller: c, autofocus: true),
    actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(d, c.text.trim().isEmpty ? null : c.text.trim()), child: const Text('OK'))]));
}
Future<String?> askText(BuildContext context, String title, String initial) => _ask(context, title, initial);

class ChannelForm extends StatefulWidget {
  const ChannelForm({super.key, this.channel});
  final Json? channel;
  @override
  State<ChannelForm> createState() => _ChannelFormState();
}

class _ChannelFormState extends State<ChannelForm> {
  late final _name = TextEditingController(text: widget.channel?['name'] as String?);
  late final _desc = TextEditingController(text: widget.channel?['description'] as String?);
  late final _cat = TextEditingController(text: widget.channel?['category'] as String?);
  late final _tags = TextEditingController(text: ((widget.channel?['tags'] as List?) ?? const []).join(', '));
  late String? _icon = widget.channel?['icon_url'] as String?;
  bool _busy = false;

  Future<void> _pickIcon() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null || !mounted) return;
    setState(() => _busy = true);
    try {
      _icon = await AppScope.read(context).api.uploadIcon(file.name, await file.readAsBytes());
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await AppScope.read(context).api.saveChannel({
        'name': _name.text.trim(), 'description': _desc.text.trim(), 'category': _cat.text.trim().isEmpty ? null : _cat.text.trim(),
        'tags': _tags.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList(), 'icon_url': _icon,
        if (widget.channel == null) 'created_by': AppScope.read(context).api.user!.id,
      }, id: widget.channel?['id'] as String?);
      if (!mounted) return;
      toast(context, 'Sent for approval — you will see “Waiting for approval” until our team reviews it.');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.channel == null ? 'Create channel' : 'Edit channel')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          ChannelIcon(keyName: _icon, size: 72),
          const SizedBox(width: 12),
          OutlinedButton.icon(onPressed: _busy ? null : _pickIcon, icon: const Icon(Icons.image), label: const Text('Choose icon')),
        ]),
        const SizedBox(height: 16),
        TextField(controller: _name, maxLength: 80, decoration: const InputDecoration(labelText: 'Name'), onChanged: (_) => setState(() {})),
        TextField(controller: _desc, maxLines: 4, maxLength: 2000, decoration: const InputDecoration(labelText: 'Description')),
        const SizedBox(height: 8),
        TextField(controller: _cat, decoration: const InputDecoration(labelText: 'Category')),
        const SizedBox(height: 12),
        TextField(controller: _tags, decoration: const InputDecoration(labelText: 'Tags (comma separated)')),
        const SizedBox(height: 8),
        const Text('Changes to name, description, category, tags or icon are reviewed again before they go live.', style: TextStyle(color: C.muted)),
        const SizedBox(height: 16),
        GradientButton(label: _busy ? 'Saving…' : 'Submit for approval', onPressed: _busy || _name.text.trim().length < 2 ? null : _save),
      ]),
    );
  }
}
