import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// `upi://pay?pa=..&pn=..&tr=..&am=..&cu=INR&tn=SkyKeep%20<ref>`
String buildUpiUri({required String upiId, required String payee, required String reference, required num amountInr}) {
  final enc = Uri.encodeComponent;
  return 'upi://pay?pa=${enc(upiId)}&pn=${enc(payee)}&tr=${enc(reference)}'
      '&am=${amountInr.toStringAsFixed(2)}&cu=INR&tn=${enc('${Config.appName} $reference')}';
}

enum UpiOutcome { success, failure, submitted, noResponse, unknown }

class UpiResult {
  const UpiResult(this.outcome, {this.txnId, this.txnRef, this.raw});
  final UpiOutcome outcome;
  final String? txnId, txnRef, raw;
}

/// Parses the UPI app response (keys are case-insensitive). Only a hint for the UI —
/// the server re-parses the raw string and decides.
UpiResult parseUpiResult(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const UpiResult(UpiOutcome.noResponse);
  final map = <String, String>{};
  for (final part in raw.split(RegExp(r'[&?]'))) {
    final i = part.indexOf('=');
    if (i <= 0) continue;
    final v = part.substring(i + 1).trim().replaceAll('+', ' ');
    String decoded;
    try { decoded = Uri.decodeComponent(v); } catch (_) { decoded = v; } // malformed %-escapes must not crash
    map[part.substring(0, i).trim().toLowerCase()] = decoded;
  }
  final status = (map['status'] ?? '').toUpperCase();
  final outcome = switch (status) {
    'SUCCESS' => UpiOutcome.success,
    'FAILURE' || 'FAILED' => UpiOutcome.failure,
    'SUBMITTED' || 'PENDING' => UpiOutcome.submitted,
    'NO_RESPONSE' => UpiOutcome.noResponse,
    _ => UpiOutcome.unknown,
  };
  return UpiResult(outcome, txnId: map['txnid'] ?? map['approvalrefno'], txnRef: map['txnref'], raw: raw);
}

/// What the native side returned.
class UpiLaunch {
  const UpiLaunch({this.response, this.noApp = false, this.cancelled = false});
  final String? response;
  final bool noApp, cancelled;
}

/// Kotlin MethodChannel 'app/upi' (Intent.createChooser + startActivityForResult).
class UpiLauncher {
  const UpiLauncher();
  static const _ch = MethodChannel('app/upi');

  Future<UpiLaunch> pay(String uri) async {
    final r = Map<String, dynamic>.from(await _ch.invokeMethod<Map>('pay', {'uri': uri}) ?? const {});
    return UpiLaunch(response: r['response'] as String?, noApp: r['no_app'] == true, cancelled: r['cancelled'] == true);
  }

  /// PNG QR code of the same upi:// URI (generated natively with ZXing). Null if it could not be made.
  Future<List<int>?> qr(String uri, {int size = 600}) async {
    try {
      return await _ch.invokeMethod<List<int>>('qr', {'uri': uri, 'size': size});
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

/// Result strings saved locally FIRST, then reported; retried with backoff until the server answers.
class PendingPaymentsQueue {
  PendingPaymentsQueue(this._prefs, {DateTime Function()? now}) : _now = now ?? DateTime.now;
  final SharedPreferences _prefs;
  final DateTime Function() _now;
  static const _key = 'pending_payments';

  List<Map<String, dynamic>> get items =>
      (jsonDecode(_prefs.getString(_key) ?? '[]') as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  Future<void> _save(List<Map<String, dynamic>> xs) => _prefs.setString(_key, jsonEncode(xs));

  Future<void> add(String orderId, String raw) async {
    final xs = items..removeWhere((e) => e['order_id'] == orderId);
    xs.add({'order_id': orderId, 'raw': raw, 'attempts': 0, 'next_at': _now().millisecondsSinceEpoch});
    await _save(xs);
  }

  /// Sends due items. Returns the server statuses by order id. Failures back off: 2^n s, max 1 h.
  Future<Map<String, String>> flush(Future<String> Function(String orderId, String raw) report) async {
    final out = <String, String>{};
    final keep = <Map<String, dynamic>>[];
    final now = _now().millisecondsSinceEpoch;
    for (final e in items) {
      if ((e['next_at'] as int) > now) {
        keep.add(e);
        continue;
      }
      try {
        out[e['order_id'] as String] = await report(e['order_id'] as String, e['raw'] as String);
      } catch (_) {
        final n = (e['attempts'] as int) + 1;
        keep.add({...e, 'attempts': n, 'next_at': now + min(3600, pow(2, n).toInt()) * 1000});
      }
    }
    await _save(keep);
    return out;
  }
}
