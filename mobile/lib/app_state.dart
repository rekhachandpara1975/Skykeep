import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import 'config.dart';
import 'services/api.dart';
import 'services/play_integrity.dart';
import 'services/status.dart';
import 'services/upi.dart';

/// Holds server status, the live plan catalog and the pending-payment queue.
class AppController extends ChangeNotifier with WidgetsBindingObserver {
  AppController({required this.api, required this.prefs, this.upi = const UpiLauncher(), this.realtime = true, this.play = const PlayIntegrity()})
      : queue = PendingPaymentsQueue(prefs);

  final Api api;
  final SharedPreferences prefs;
  final UpiLauncher upi;
  final PendingPaymentsQueue queue;
  final bool realtime;
  final PlayIntegrity play;
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
      await api.ensureGuest(); // every user is at least a guest (organic or from ads)
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

  /// Play Store build only: Play Integrity check → free 15 GB tier (server decides in play-verify).
  Future<void> syncPlay() async {
    if (!Config.playStore || status.isGuest || status.playVerified || _playSyncing) return;
    _playSyncing = true;
    try {
      final nonce = await api.playChallenge();
      if (await api.playVerify(await play.token(nonce), nonce)) await refresh();
    } catch (e) {
      debugPrint('play integrity failed: $e');
    } finally {
      _playSyncing = false;
    }
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
