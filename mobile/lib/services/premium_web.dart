import 'dart:convert';

import '../config.dart';

/// WEBSITE_URL/subscribe?app=1[&free=ids][&paused=1]
Uri premiumPageUrl({required List<String> freePlanIds, required bool paymentsAvailable, String base = Config.websiteUrl}) {
  final q = <String, String>{'app': '1'};
  if (freePlanIds.isNotEmpty) q['free'] = freePlanIds.join(',');
  if (!paymentsAvailable) q['paused'] = '1';
  return Uri.parse('$base/subscribe').replace(queryParameters: q);
}

/// Only WEBSITE_URL/subscribe and /d may load in the WebView.
bool allowWebNavigation(String url, {String base = Config.websiteUrl}) {
  final u = Uri.tryParse(url);
  final b = Uri.parse(base);
  if (u == null || u.scheme != 'https' || u.host != b.host || (u.hasPort && u.port != 443)) return false;
  return u.path == '/subscribe' || u.path == '/d';
}

final _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', caseSensitive: false);

class BuyMessage {
  const BuyMessage(this.planId, this.shownPriceInr);
  final String planId;
  final num? shownPriceInr;
}

/// `{type:"buy", plan_id:"<uuid>"}` → BuyMessage, anything else → null.
BuyMessage? parseBuyMessage(String message) {
  try {
    final m = jsonDecode(message);
    if (m is! Map || m['type'] != 'buy') return null;
    final id = m['plan_id'];
    if (id is! String || !_uuid.hasMatch(id)) return null;
    final p = m['price_inr'];
    return BuyMessage(id, p is num ? p : null);
  } catch (_) {
    return null;
  }
}
