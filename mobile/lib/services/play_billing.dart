import 'package:flutter/services.dart';

/// One owned / just-bought subscription as reported by the Play Billing Library.
class PlayPurchase {
  const PlayPurchase({required this.productId, required this.purchaseToken, this.state = 'purchased'});
  final String productId, purchaseToken, state;
  Map<String, String> toJson() => {'productId': productId, 'purchaseToken': purchaseToken};

  static PlayPurchase fromMap(Map m) => PlayPurchase(
      productId: '${m['productId'] ?? ''}', purchaseToken: '${m['purchaseToken'] ?? ''}', state: '${m['state'] ?? 'unspecified'}');
}

/// Google Play (Play build only) — Kotlin MethodChannel 'app/play'.
/// Integrity check for the free tier, and Play Billing with User Choice Billing (Google shows the choice screen).
/// Nothing here grants access: tokens go to the server (play-verify / play-purchase), which decides.
class PlayBilling {
  PlayBilling();
  static const _ch = MethodChannel('app/play');
  bool _listening = false;

  /// Google Play path finished (bought / pending / cancelled).
  void Function(String result, List<PlayPurchase> purchases)? onPurchases;

  /// User picked "Pay with UPI" on Google's choice screen.
  void Function(String externalTransactionToken, List<String> products)? onUserChoice;

  void _listen() {
    if (_listening) return;
    _listening = true;
    _ch.setMethodCallHandler((call) async {
      final a = Map<String, dynamic>.from(call.arguments as Map? ?? const {});
      switch (call.method) {
        case 'purchases':
          onPurchases?.call('${a['result']}', ((a['purchases'] as List?) ?? const []).map((e) => PlayPurchase.fromMap(e as Map)).toList());
        case 'userChoice':
          onUserChoice?.call('${a['externalTransactionToken']}', ((a['products'] as List?) ?? const []).map((e) => '$e').toList());
      }
      return null;
    });
  }

  Future<String> integrityToken(String nonce) async => (await _ch.invokeMethod<String>('integrityToken', {'nonce': nonce}))!;

  /// Returns "ready" when connected. Only call when the server says Play billing is on.
  Future<String> connect() async {
    _listen();
    return await _ch.invokeMethod<String>('connect', {'enabled': true}) ?? 'error';
  }

  /// "ok" when Google's sheet opened; the outcome arrives via [onPurchases] or [onUserChoice].
  Future<String> buy({required String productId, String? basePlanId, required String accountId}) async =>
      await _ch.invokeMethod<String>('buy', {'productId': productId, 'basePlanId': basePlanId, 'accountId': accountId}) ?? 'error';

  Future<List<PlayPurchase>> queryPurchases() async =>
      ((await _ch.invokeMethod<List>('queryPurchases')) ?? const []).map((e) => PlayPurchase.fromMap(e as Map)).toList();
}

/// Indian states / UTs for Google's tax address (code, name).
const indianStates = <(String, String)>[
  ('AN', 'Andaman and Nicobar Islands'), ('AP', 'Andhra Pradesh'), ('AR', 'Arunachal Pradesh'), ('AS', 'Assam'),
  ('BR', 'Bihar'), ('CH', 'Chandigarh'), ('CT', 'Chhattisgarh'), ('DN', 'Dadra and Nagar Haveli and Daman and Diu'),
  ('DL', 'Delhi'), ('GA', 'Goa'), ('GJ', 'Gujarat'), ('HR', 'Haryana'), ('HP', 'Himachal Pradesh'),
  ('JK', 'Jammu and Kashmir'), ('JH', 'Jharkhand'), ('KA', 'Karnataka'), ('KL', 'Kerala'), ('LA', 'Ladakh'),
  ('LD', 'Lakshadweep'), ('MP', 'Madhya Pradesh'), ('MH', 'Maharashtra'), ('MN', 'Manipur'), ('ML', 'Meghalaya'),
  ('MZ', 'Mizoram'), ('NL', 'Nagaland'), ('OR', 'Odisha'), ('PY', 'Puducherry'), ('PB', 'Punjab'),
  ('RJ', 'Rajasthan'), ('SK', 'Sikkim'), ('TN', 'Tamil Nadu'), ('TG', 'Telangana'), ('TR', 'Tripura'),
  ('UP', 'Uttar Pradesh'), ('UT', 'Uttarakhand'), ('WB', 'West Bengal'),
];
