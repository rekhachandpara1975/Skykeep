import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../config.dart';
import '../services/api.dart';
import '../services/status.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'channels.dart' show askText, mimeFor;
import 'login_sheet.dart';
import 'profile.dart' show ProfileButton;
import 'premium.dart';

class CloudScreen extends StatefulWidget {
  const CloudScreen({super.key});
  @override
  State<CloudScreen> createState() => _CloudScreenState();
}

class _CloudScreenState extends State<CloudScreen> {
  final _path = <Json>[]; // folder breadcrumb
  List<Json> _folders = const [], _files = const [];
  bool _loading = false, _error = false;
  final _uploads = <String, double>{};

  String? get _folderId => _path.isEmpty ? null : _path.last['id'] as String;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loading && _folders.isEmpty && _files.isEmpty && !AppScope.read(context).api.isGuest) _load();
  }

  Future<void> _load() async {
    final api = AppScope.read(context).api;
    if (api.isGuest) return;
    setState(() { _loading = true; _error = false; });
    try {
      final r = await Future.wait([api.cloudFolders(_folderId), api.cloudFiles(_folderId)]);
      _folders = r[0]; _files = r[1];
    } catch (_) {
      _error = true;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _upload(FileType type) async {
    final app = AppScope.read(context);
    final picked = await FilePicker.pickFiles(type: type);
    for (final f in picked) {
      if (!mounted) return;
      setState(() => _uploads[f.name] = 0);
      try {
        await app.api.uploadCloud(
          name: f.name, size: await f.length() ?? 0, mime: mimeFor(f.extension), folderId: _folderId,
          open: f.readAsByteStream,
          onProgress: (p) => mounted ? setState(() => _uploads[f.name] = p) : null,
        );
      } catch (e) {
        if (mounted) toast(context, e.toString().contains('storage_full') ? 'Not enough storage for ${f.name}' : 'Upload failed: ${f.name}');
      }
      if (mounted) setState(() => _uploads.remove(f.name));
    }
    await app.refresh();
    await _load();
  }

  Future<void> _fileMenu(Json f) async {
    final api = AppScope.read(context).api;
    final action = await showModalBottomSheet<String>(context: context, backgroundColor: C.surface, builder: (c) => SafeArea(
      child: Wrap(children: [
        ListTile(leading: const Icon(Icons.open_in_new), title: const Text('Open'), onTap: () => Navigator.pop(c, 'open')),
        ListTile(leading: const Icon(Icons.edit), title: const Text('Rename'), onTap: () => Navigator.pop(c, 'rename')),
        ListTile(leading: const Icon(Icons.drive_file_move), title: const Text('Move'), onTap: () => Navigator.pop(c, 'move')),
        ListTile(leading: const Icon(Icons.delete, color: C.danger), title: const Text('Delete'), onTap: () => Navigator.pop(c, 'delete')),
      ])));
    if (!mounted || action == null) return;
    try {
      switch (action) {
        case 'open':
          final url = await api.fileUrl(f['id'] as String);
          if (url != null) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        case 'rename':
          final n = await askText(context, 'Rename', f['name'] as String);
          if (n != null) await api.renameFile(f['id'] as String, n);
        case 'move':
          final folders = await api.allFolders();
          if (!mounted) return;
          final to = await showDialog<Object>(context: context, builder: (c) => SimpleDialog(title: const Text('Move to'), children: [
            SimpleDialogOption(onPressed: () => Navigator.pop(c, ''), child: const Text('My files (top)')),
            for (final d in folders) SimpleDialogOption(onPressed: () => Navigator.pop(c, d['id']), child: Text(d['name'] as String)),
          ]));
          if (to != null) await api.moveFile(f['id'] as String, to == '' ? null : to as String);
        case 'delete':
          final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
            title: Text('Delete ${f['name']}?'), content: const Text('This cannot be undone.'),
            actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
              FilledButton(style: FilledButton.styleFrom(backgroundColor: C.danger), onPressed: () => Navigator.pop(c, true), child: const Text('Delete'))]));
          if (ok == true) await api.deleteFile(f['id'] as String);
      }
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
    if (mounted) { await AppScope.read(context).refresh(); await _load(); }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.status;
    final canUpload = !app.api.isGuest && s.quotaBytes > s.usedBytes;
    return Scaffold(
      appBar: AppBar(
        title: Text(_path.isEmpty ? 'Cloud' : _path.last['name'] as String),
        leading: _path.isEmpty ? null : BackButton(onPressed: () { setState(() => _path.removeLast()); _load(); }),
        actions: [
          if (!app.api.isGuest && s.quotaBytes > 0)
            IconButton(tooltip: 'New folder', icon: const Icon(Icons.create_new_folder), onPressed: () async {
              final n = await askText(context, 'New folder', '');
              if (n == null) return;
              await app.api.createFolder(n, _folderId);
              _load();
            }),
          if (_path.isEmpty) const ProfileButton(),
        ],
      ),
      floatingActionButton: canUpload
          ? PopupMenuButton<FileType>(
              tooltip: 'Upload',
              onSelected: _upload,
              itemBuilder: (_) => const [
                PopupMenuItem(value: FileType.image, child: Text('Photos')),
                PopupMenuItem(value: FileType.video, child: Text('Videos')),
                PopupMenuItem(value: FileType.any, child: Text('Files')),
              ],
              child: const FloatingActionButton(onPressed: null, child: Icon(Icons.add, size: 30)),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async { await app.refresh(); await _load(); },
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
          Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Storage', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                const SizedBox(height: 4),
                Semantics(
                  label: 'Storage ${formatBytes(s.usedBytes)} of ${formatBytes(s.quotaBytes)} used',
                  excludeSemantics: true,
                  child: Text(s.quotaBytes == 0 ? 'No cloud storage yet'
                      : '${formatBytes((s.quotaBytes - s.usedBytes).clamp(0, s.quotaBytes))} free of ${formatBytes(s.quotaBytes)}',
                      style: const TextStyle(color: C.muted)),
                ),
                if (s.quotaBytes > 0) Text('${formatBytes(s.usedBytes)} of ${formatBytes(s.quotaBytes)} used',
                    style: const TextStyle(color: C.muted, fontSize: 12)),
                if (!app.api.isGuest && !s.hasPlan && s.plansVisible && !s.freeMode && !Config.playStore && s.quotaBytes > 0) ...[
                  const SizedBox(height: 10),
                  FilledButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PremiumScreen())),
                      style: FilledButton.styleFrom(minimumSize: const Size(96, 40)), child: const Text('Upgrade')),
                ],
              ])),
              StorageRing(used: s.usedBytes, quota: s.quotaBytes),
            ]),
            CloudPrompt(status: s, isGuest: app.api.isGuest),
          ]))),
          const SizedBox(height: 12),
          for (final u in _uploads.entries)
            ListTile(leading: const Icon(Icons.upload_file), title: Text(u.key, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: LinearProgressIndicator(value: u.value)),
          if (_error) ErrorRetry(onRetry: _load),
          if (_loading && _files.isEmpty && _folders.isEmpty) ...[const Skeleton(), const Skeleton()],
          if (_folders.isNotEmpty || _files.isNotEmpty)
            Padding(padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                child: Text(_path.isEmpty ? 'My files' : 'In ${_path.last['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17))),
          for (final d in _folders)
            ListTile(
              leading: const Icon(Icons.folder_rounded, color: C.folder, size: 36),
              title: Text(d['name'] as String),
              onTap: () { setState(() => _path.add(d)); _load(); },
              trailing: IconButton(tooltip: 'Delete folder', icon: const Icon(Icons.delete_outline), onPressed: () async {
                await app.api.deleteFolder(d['id'] as String);
                _load();
              }),
            ),
          for (final f in _files)
            ListTile(
              leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(10)),
                  child: Icon(_iconFor(f['mime'] as String?), color: C.primary)),
              title: Text(f['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(formatBytes(f['size_bytes'] as num)),
              onTap: () => _fileMenu(f),
            ),
          if (!_loading && !app.api.isGuest && _files.isEmpty && _folders.isEmpty && _uploads.isEmpty && s.quotaBytes > 0)
            const Padding(padding: EdgeInsets.only(top: 32), child: Text('No files yet. Tap Upload to back up photos, videos and files.',
                textAlign: TextAlign.center, style: TextStyle(color: C.muted))),
        ]),
      ),
    );
  }
}

IconData _iconFor(String? mime) => (mime ?? '').startsWith('image/') ? Icons.image
    : (mime ?? '').startsWith('video/') ? Icons.movie : Icons.insert_drive_file;

/// What to say about storage, depending on the mode (never shows prices when plans are hidden).
class CloudPrompt extends StatelessWidget {
  const CloudPrompt({super.key, required this.status, required this.isGuest});
  final AppStatus status;
  final bool isGuest;
  @override
  Widget build(BuildContext context) {
    final freeStorage = status.freeMode || Config.playStore;
    if (isGuest) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 12),
        Text(freeStorage ? 'Log in to get 15 GB free cloud storage.' : 'Log in to use cloud storage.'),
        const SizedBox(height: 8),
        GradientButton(label: 'Log in', onPressed: () => requireMember(context, reason: 'Log in for cloud storage')),
      ]);
    }
    if (status.quotaBytes > 0) return const SizedBox();
    if (Config.playStore) return const Padding(padding: EdgeInsets.only(top: 12), child: Text('Verifying your device for 15 GB free storage…', style: TextStyle(color: C.muted)));
    if (status.plansVisible) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 12),
        const Text('Get Premium for 2 TB of cloud storage.'),
        const SizedBox(height: 8),
        GradientButton(label: 'See Premium', icon: Icons.workspace_premium,
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PremiumScreen()))),
      ]);
    }
    return const Padding(padding: EdgeInsets.only(top: 12), child: Text('Cloud storage is for Premium members.', style: TextStyle(color: C.muted)));
  }
}
