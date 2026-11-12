import 'package:flutter/services.dart';

/// Play Store build only — Kotlin MethodChannel 'app/play'.
/// The Play Integrity token goes to the play-verify edge function, which grants the free 15 GB tier.
/// The Play build never sells anything (UPI checkout exists only in the website / ads APKs).
class PlayIntegrity {
  const PlayIntegrity();
  static const _ch = MethodChannel('app/play');

  Future<String> token(String nonce) async => (await _ch.invokeMethod<String>('integrityToken', {'nonce': nonce}))!;
}
