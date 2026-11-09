import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:skykeep/screens/premium.dart';

/// Runs before every test file: fakes the plans WebView and allows tiny golden pixel differences
/// between Windows/Linux rasterizers.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  premiumWebBuilder = (url, onMessage) => FakePremiumWeb(url: url, onMessage: onMessage);
  if (goldenFileComparator is LocalFileComparator) {
    final base = (goldenFileComparator as LocalFileComparator).basedir;
    goldenFileComparator = _TolerantComparator(Uri.directory(base.toFilePath()).resolve('golden_test.dart'));
  }
  await testMain();
}

/// Shows the URL it would load and buy buttons that post the same message the website sends.
class FakePremiumWeb extends StatelessWidget {
  const FakePremiumWeb({super.key, required this.url, required this.onMessage});
  final Uri url;
  final void Function(String) onMessage;
  static Uri? lastUrl;
  @override
  Widget build(BuildContext context) {
    lastUrl = url;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('WEB ${url.path}', key: const Key('fake-web')),
      Text(url.query, key: const Key('fake-web-query')),
    ]);
  }
}

class _TolerantComparator extends LocalFileComparator {
  _TolerantComparator(super.testFile);
  static const tolerance = 0.02; // 2 % of pixels

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(imageBytes, await getGoldenBytes(golden));
    if (result.passed || result.diffPercent <= tolerance) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}
