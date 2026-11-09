import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import 'services/api.dart';
import 'services/status.dart';
import 'services/upi.dart';

/// Holds server status, the live plan catalog and the pending-payment queue.
class AppController extends ChangeNotifier with WidgetsBindingObserver {
  AppController({required this.api, required this.prefs, this.upi = const UpiLauncher(), this.realtime = true})
      : queue = PendingPaymentsQueue(prefs);

  final Api api;
  final SharedPreferences prefs;
  final UpiLauncher upi;
  final PendingPaymentsQueue queue;
  final bool realtime;

  AppStatus status = const AppStatus();
  List<Json> plans = const [];
  Json? pendingOrder;
  RealtimeChannel? _channel;
  Timer? _poll;

  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    await refresh();
    unawaited(flushPayments());
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
      refresh();
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
