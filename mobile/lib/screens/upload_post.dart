import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../services/status.dart';
import '../services/thumbs.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'channels.dart' show mimeFor;

/// A chosen file, already read into memory.
class PickedMedia {
  const PickedMedia({required this.name, required this.bytes, this.path});
  final String name;
  final Uint8List bytes;
  final String? path;
  int get size => bytes.length;
  String get extension => name.contains('.') ? name.split('.').last : '';
}

typedef MediaPicker = Future<PickedMedia?> Function(FileType type);

Future<PickedMedia?> _pick(FileType type) async {
  final f = await FilePicker.pickFile(type: type);
  if (f == null) return null;
  return PickedMedia(name: f.name, bytes: Uint8List.fromList(await f.readAsBytes()), path: f.path);
}

/// New post: media + title, an optional thumbnail (auto-cut from the video when left empty),
/// an optional trailer that plays before the full video, and "Premium only".
class UploadPostScreen extends StatefulWidget {
  const UploadPostScreen({super.key, required this.channelId, this.picker = _pick});
  final String channelId;
  final MediaPicker picker;
  @override
  State<UploadPostScreen> createState() => _UploadPostScreenState();
}

class _UploadPostScreenState extends State<UploadPostScreen> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  PickedMedia? _media, _trailer, _customThumb;
  VideoFrame? _auto;
  bool _busy = false, _premium = false, _cutting = false;

  bool get _isVideo => (mimeFor(_media?.extension) ?? '').startsWith('video/');
  bool get _isImage => (mimeFor(_media?.extension) ?? '').startsWith('image/');

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _chooseMedia() async {
    final f = await widget.picker(FileType.media);
    if (f == null || !mounted) return;
    setState(() { _media = f; _auto = null; if (_title.text.trim().isEmpty) _title.text = f.name.split('.').first; });
    if ((mimeFor(f.extension) ?? '').startsWith('video/') && f.path != null) {
      setState(() => _cutting = true);
      final frame = await AppScope.read(context).thumbs.frame(f.path!);
      if (mounted && _media == f) setState(() { _auto = frame; _cutting = false; });
    }
  }

  Future<void> _chooseThumb() async {
    final f = await widget.picker(FileType.image);
    if (f != null && mounted) setState(() => _customThumb = f);
  }

  Future<void> _chooseTrailer() async {
    final f = await widget.picker(FileType.video);
    if (f != null && mounted) setState(() => _trailer = f);
  }

  Future<void> _post() async {
    final media = _media;
    if (media == null) { toast(context, 'Choose a video or photo first'); return; }
    if (_title.text.trim().isEmpty) { toast(context, 'Add a title'); return; }
    final app = AppScope.read(context);
    setState(() => _busy = true);
    try {
      final thumb = _customThumb;
      await app.api.uploadPost(
        channelId: widget.channelId, title: _title.text.trim(),
        description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        fileName: media.name, bytes: media.bytes, mime: mimeFor(media.extension),
        thumbBytes: thumb != null ? thumb.bytes : _auto?.jpeg,
        thumbMime: thumb != null ? mimeFor(thumb.extension) : 'image/jpeg',
        trailerBytes: _trailer?.bytes,
        trailerName: _trailer?.name, trailerMime: mimeFor(_trailer?.extension),
        premium: _premium, durationS: _auto == null || _auto!.duration == Duration.zero ? null : _auto!.duration.inSeconds,
      );
      unawaited(app.refresh()); // the storage card shows the new upload straight away
      if (!mounted) return;
      toast(context, 'Posted');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) { toast(context, friendlyError(e)); setState(() => _busy = false); }
    }
  }

  Widget _thumbPreview() {
    final Widget inner;
    if (_customThumb != null) {
      inner = Image.memory(_customThumb!.bytes, fit: BoxFit.cover);
    } else if (_auto != null) {
      inner = Image.memory(_auto!.jpeg, fit: BoxFit.cover);
    } else if (_isImage) {
      inner = Image.memory(_media!.bytes, fit: BoxFit.cover);
    } else {
      inner = _cutting ? const Center(child: CircularProgressIndicator()) : const Icon(Icons.movie_outlined, size: 40, color: C.muted);
    }
    return ClipRRect(borderRadius: BorderRadius.circular(12),
        child: AspectRatio(aspectRatio: 16 / 9, child: Container(color: C.surface2, alignment: Alignment.center, child: SizedBox.expand(child: inner))));
  }

  @override
  Widget build(BuildContext context) {
    final media = _media;
    final thumbNote = _customThumb != null ? 'Your thumbnail'
        : _auto != null ? 'Created automatically from your video'
        : _isImage ? 'Your photo is used as the thumbnail' : 'A thumbnail is created automatically from your video';
    return Scaffold(
      appBar: AppBar(title: const Text('New post')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: ListTile(
          leading: Icon(media == null ? Icons.add_photo_alternate_outlined : (_isVideo ? Icons.movie_outlined : Icons.image_outlined), color: C.primary),
          title: Text(media?.name ?? 'Choose video or photo', maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: media == null ? null : Text(formatBytes(media.size)),
          trailing: TextButton(onPressed: _busy ? null : _chooseMedia, child: Text(media == null ? 'Choose' : 'Change')),
          onTap: _busy ? null : _chooseMedia,
        )),
        const SizedBox(height: 12),
        TextField(controller: _title, maxLength: 120, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Title')),
        TextField(controller: _desc, maxLines: 3, maxLength: 2000, decoration: const InputDecoration(labelText: 'Description (optional)')),
        const SizedBox(height: 8),
        const Text('Thumbnail', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        _thumbPreview(),
        const SizedBox(height: 6),
        Text(thumbNote, style: const TextStyle(color: C.muted, fontSize: 12)),
        Wrap(spacing: 8, children: [
          TextButton.icon(onPressed: _busy ? null : _chooseThumb, icon: const Icon(Icons.image_outlined), label: Text(_customThumb == null ? 'Upload thumbnail (optional)' : 'Change thumbnail')),
          if (_customThumb != null)
            TextButton(onPressed: _busy ? null : () => setState(() => _customThumb = null), child: const Text('Use automatic')),
        ]),
        const Divider(height: 28),
        const Text('Trailer (optional)', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('A short preview that plays first. Viewers with access continue straight into the full video; others watch only the trailer.',
            style: TextStyle(color: C.muted, fontSize: 12)),
        const SizedBox(height: 4),
        if (_trailer == null)
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: _busy ? null : _chooseTrailer, icon: const Icon(Icons.theaters_outlined), label: const Text('Add trailer')))
        else
          ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.theaters_outlined, color: C.primary),
              title: Text(_trailer!.name, maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text(formatBytes(_trailer!.size)),
              trailing: IconButton(tooltip: 'Remove trailer', icon: const Icon(Icons.close), onPressed: _busy ? null : () => setState(() => _trailer = null))),
        SwitchListTile(
          contentPadding: EdgeInsets.zero, value: _premium, onChanged: _busy ? null : (v) => setState(() => _premium = v),
          title: const Text('Full video for Premium members only'),
          subtitle: const Text('Everyone else sees the trailer (or a lock if there is none).'),
        ),
        const SizedBox(height: 12),
        GradientButton(label: _busy ? 'Uploading…' : 'Post', onPressed: _busy ? null : _post),
      ]),
    );
  }
}
