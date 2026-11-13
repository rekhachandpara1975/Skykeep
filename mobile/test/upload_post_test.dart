import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skykeep/screens/upload_post.dart';
import 'package:skykeep/services/thumbs.dart';
import 'package:skykeep/theme.dart';

import 'fakes.dart';

// a valid 1x1 PNG so Image.memory can decode it
final _png = Uint8List.fromList(const [
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84,
  120, 156, 99, 248, 255, 255, 63, 0, 5, 254, 2, 254, 167, 53, 129, 132, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
]);

class _FakeThumbs extends Thumbs {
  _FakeThumbs(this.frameOrNull);
  final VideoFrame? frameOrNull;
  String? asked;
  @override
  Future<VideoFrame?> frame(String path, {int maxWidth = 640}) async {
    asked = path;
    return frameOrNull;
  }
}

PlatformFile _file(String name, {int size = 3, String? path}) => PlatformFile(name: name, size: size, bytes: Uint8List(size), path: path ?? '/tmp/$name');

void main() {
  Future<void> post(WidgetTester t) async {
    await t.ensureVisible(find.widgetWithText(GradientButton, 'Post'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(GradientButton, 'Post'));
    await t.pumpAndSettle();
  }

  testWidgets('video without a thumbnail: one is cut automatically and uploaded with the post', (t) async {
    final api = FakeApi();
    final thumbs = _FakeThumbs(VideoFrame(_png, const Duration(seconds: 125)));
    await pumpApp(t, api, UploadPostScreen(channelId: 'c1', picker: (type) async => _file('clip.mp4', path: '/tmp/clip.mp4')), thumbs: thumbs);
    expect(find.text('A thumbnail is created automatically from your video'), findsOneWidget);
    await t.tap(find.text('Choose'));
    await t.pumpAndSettle();
    expect(thumbs.asked, '/tmp/clip.mp4');
    expect(find.text('Created automatically from your video'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Title'), findsOneWidget);
    await post(t);
    expect(api.uploads, hasLength(1));
    expect(api.uploads.single['title'], 'clip'); // from the file name
    expect(api.uploads.single['thumb'], _png);
    expect(api.uploads.single['thumbMime'], 'image/jpeg');
    expect(api.uploads.single['durationS'], 125);
    expect(api.uploads.single['trailer'], isNull);
    expect(api.uploads.single['premium'], false);
  });

  testWidgets('own thumbnail replaces the automatic one; trailer and Premium-only are sent', (t) async {
    final api = FakeApi();
    final picks = <FileType>[];
    await pumpApp(t, api, UploadPostScreen(channelId: 'c1', picker: (type) async {
      picks.add(type);
      return switch (type) {
        FileType.image => PlatformFile(name: 'cover.png', size: _png.length, bytes: _png),
        FileType.video => _file('trailer.mp4', size: 5),
        _ => _file('movie.mp4', size: 9),
      };
    }), thumbs: _FakeThumbs(VideoFrame(_png, Duration.zero)));
    await t.tap(find.text('Choose'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Upload thumbnail (optional)'));
    await t.tap(find.text('Upload thumbnail (optional)'));
    await t.pumpAndSettle();
    expect(find.text('Your thumbnail'), findsOneWidget);
    await t.ensureVisible(find.text('Add trailer'));
    await t.tap(find.text('Add trailer'));
    await t.pumpAndSettle();
    expect(find.text('trailer.mp4'), findsOneWidget);
    await t.ensureVisible(find.byType(SwitchListTile));
    await t.tap(find.byType(SwitchListTile));
    await t.pumpAndSettle();
    await post(t);
    final u = api.uploads.single;
    expect(picks, [FileType.media, FileType.image, FileType.video]);
    expect(u['thumb'], _png);
    expect(u['thumbMime'], 'image/png');
    expect((u['trailer'] as List).length, 5);
    expect(u['trailerName'], 'trailer.mp4');
    expect(u['premium'], true);
  });

  testWidgets('a photo is its own thumbnail and nothing is generated; posting needs a file', (t) async {
    final api = FakeApi();
    final thumbs = _FakeThumbs(null);
    await pumpApp(t, api, UploadPostScreen(channelId: 'c1', picker: (type) async => PlatformFile(name: 'pic.jpg', size: _png.length, bytes: _png)), thumbs: thumbs);
    await post(t);
    expect(api.uploads, isEmpty); // nothing chosen yet
    await t.tap(find.text('Choose'));
    await t.pumpAndSettle();
    expect(thumbs.asked, isNull);
    expect(find.text('Your photo is used as the thumbnail'), findsOneWidget);
    await post(t);
    expect(api.uploads.single['thumb'], isNull); // the API uses the photo itself
    expect(api.uploads.single['mime'], 'image/jpeg');
  });
}
