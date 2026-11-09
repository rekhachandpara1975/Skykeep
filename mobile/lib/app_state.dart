import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import 'config.dart';
import 'services/api.dart';
import 'services/play_billing.dart';
import 'services/status.dart';
import 'services/upi.dart';

/// Holds server status, the live plan catalog and the pending-payment queue.
class AppController extends ChangeNotifier with WidgetsBindingObserver {
  AppController({required this.api, required this.prefs, this.upi = const UpiLauncher(), this.realtime = true, PlayBilling? play})
      : queue = PendingPaymentsQueue(prefs),
        play = play ?? PlayBilling();

  final Api api;
  final SharedPreferences prefs;
  final UpiLauncher upi;
  final PendingPaymentsQueue queue;
  final bool realtime;
  final PlayBilling play;
  bool _playSyncing = false;

  AppStatus status = const AppStatus();
  List<Json> plans = const [];
  Json? pendingOrder;
  RealtimeChannel? _channel;
  Timer? _poll;

  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    await refresh();
    unawaited(flushPayments());
    unawaited(syncPlay());
    if (realtime) _channel = api.subscribeMode(() => refresh());
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    if (_channel != null) api.unsubscribe(_channel!);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      flushPayments();
      refresh().then((_) => syncPlay());
    }
  }

  Future<void> refresh() async {
    try {
      final r = await Future.wait([api.myStatus(), api.planOffers(), api.activePlans()]);
      status = AppStatus.fromServer(r[0] as Json, r[1] as Json);
      plans = r[2] as List<Json>;
      pendingOrder = status.isGuest ? null : await api.latestPendingOrder();
      notifyListeners();
    } catch (e) {
      debugPrint('status refresh failed: $e');
    }
  }

  /// Live catalog lookup; refetches once if the plan is unknown.
  Future<Json?> findPlan(String id) async {
    Json? hit() => plans.where((p) => p['id'] == id).firstOrNull;
    if (hit() != null) return hit();
    try {
      plans = await api.activePlans();
    } catch (_) {}
    return hit();
  }

  /// Play build only: Integrity check for the free tier, then (when the server turned Play billing on)
  /// connect Billing and send owned subscriptions to the server so purchases are recovered on resume.
  Future<void> syncPlay() async {
    if (!Config.playStore || status.isGuest || _playSyncing) return;
    _playSyncing = true;
    try {
      if (!status.playVerified) {
        final nonce = await api.playChallenge();
        if (await api.playVerify(await play.integrityToken(nonce), nonce)) await refresh();
      }
      if (status.playBillingEnabled) {
        play.onPurchases ??= (result, purchases) => recordPlayPurchases(purchases);
        if (await play.connect() == 'ready') await recordPlayPurchases(await play.queryPurchases());
      }
    } catch (e) {
      debugPrint('play sync failed: $e');
    } finally {
      _playSyncing = false;
    }
  }

  Future<void> recordPlayPurchases(List<PlayPurchase> purchases) async {
    final bought = purchases.where((p) => p.state == 'purchased' && p.purchaseToken.isNotEmpty).toList();
    if (bought.isEmpty) return;
    await api.playPurchase([for (final p in bought) p.toJson()]);
    await refresh();
  }

  Future<Map<String, String>> flushPayments() async {
    final r = await queue.flush(api.reportResult);
    if (r.isNotEmpty) await refresh();
    return r;
  }
}

class AppScope extends InheritedNotifier<AppController> {
  const AppScope({super.key, required AppController controller, required super.child}) : super(notifier: controller);
  static AppController of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
  static AppController read(BuildContext c) => c.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
