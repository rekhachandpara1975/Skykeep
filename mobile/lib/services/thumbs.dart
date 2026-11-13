import 'package:flutter/services.dart';

/// A poster frame cut from a local video + its length.
class VideoFrame {
  const VideoFrame(this.jpeg, this.duration);
  final Uint8List jpeg;
  final Duration duration;
}

/// Auto thumbnails (Kotlin MethodChannel 'app/thumb', MediaMetadataRetriever). Never throws: null = no frame.
class Thumbs {
  const Thumbs();
  static const _ch = MethodChannel('app/thumb');

  Future<VideoFrame?> frame(String path, {int maxWidth = 640}) async {
    try {
      final r = await _ch.invokeMethod<Map>('frame', {'path': path, 'maxWidth': maxWidth});
      if (r == null) return null;
      return VideoFrame(Uint8List.fromList(List<int>.from(r['jpeg'] as List)), Duration(milliseconds: (r['durationMs'] as num?)?.toInt() ?? 0));
    } catch (_) {
      return null;
    }
  }
}
