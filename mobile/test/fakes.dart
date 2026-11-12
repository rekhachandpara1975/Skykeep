import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skykeep/app_state.dart';
import 'package:skykeep/main.dart';
import 'package:skykeep/services/api.dart';
import 'package:skykeep/services/play_integrity.dart';
import 'package:skykeep/services/upi.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

const planMonthly = '11111111-1111-1111-1111-111111111111';
const planYearly = '22222222-2222-2222-2222-222222222222';

Json statusJson({
  bool guest = false,
  String source = 'ads',
  bool freeMode = false,
  bool plansVisible = true,
  bool paymentsAvailable = true,
  bool hasPlan = false,
  bool premium = false,
  String access = 'none',
  int quota = 0,
  int used = 0,
}) =>
    {
      'user_id': 'u1', 'is_guest': guest, 'is_admin': false, 'source': source, 'has_ads_access': source == 'ads',
      'is_premium': premium, 'has_plan': hasPlan, 'plan_name': hasPlan ? 'Yearly' : null,
      'plan_ends_at': hasPlan ? '2027-11-09T00:00:00Z' : null, 'used_bytes': used, 'quota_bytes': quota,
      'free_mode': freeMode, 'paid_enabled': !freeMode, 'access_status': access, 'payments_available': paymentsAvailable,
      'free_plans_for': 'none', 'plans_visible': plansVisible, 'play_verified': false, 'play_billing_enabled': false,
      'display_name': guest ? null : 'Asha',
    };

class FakeApi extends Api {
  FakeApi({this.guest = false, Json? status, this.freePlanIds = const [], this.posts = const [], this.channelsList = const []})
      : status = status ?? statusJson(guest: guest);
  bool guest;
  Json status;
  List<String> freePlanIds;
  List<Json> posts, channelsList;
  List<Json> plansList = [
    {'id': planMonthly, 'name': 'Monthly', 'price_inr': 99, 'duration_days': 30},
    {'id': planYearly, 'name': 'Yearly', 'price_inr': 799, 'duration_days': 365},
  ];
  Json? order;
  final reported = <String>[];
  bool reportFails = false;
  String reportStatus = 'paid';
  String orderStatusValue = 'pending';

  @override
  bool get isGuest => guest;
  @override
  User? get user => null;
  @override
  Future<Json> myStatus() async => status;
  @override
  Future<Json> planOffers() async =>
      {'free_plan_ids': freePlanIds, 'payments_available': status['payments_available'], 'plans_visible': status['plans_visible']};
  @override
  Future<List<Json>> activePlans() async => plansList;
  @override
  Future<Json?> latestPendingOrder() async => null;
  @override
  Future<Json> createOrder(String planId) async => order ??
      {'order_id': 'o1', 'reference': 'SK20261109ABCDEF12', 'amount_inr': 799, 'upi_id': 'shop@okaxis', 'payee_name': 'SkyKeep Shop'};
  @override
  Future<String> reportResult(String orderId, String raw) async {
    if (reportFails) throw Exception('offline');
    reported.add(raw);
    return reportStatus;
  }

  @override
  Future<Json?> orderStatus(String orderId) async => {'status': orderStatusValue, 'reference': 'SK20261109ABCDEF12'};
  @override
  Future<Json> claimFreePlan(String planId) async => {'plan_name': 'Monthly', 'ends_at': '2026-12-09T00:00:00Z'};
  @override
  Future<String> requestFullAccess() async => 'pending';
  @override
  Future<List<Json>> paymentHistory() async => const [];
  @override
  Future<List<Json>> latestPosts({int page = 0, String? category, String? query}) async => page == 0 ? posts : const [];
  @override
  Future<List<String>> categories() async => const ['Tech', 'Travel'];
  @override
  Future<List<Json>> channels(String tab) async => tab == 'discover' ? channelsList : const [];
  @override
  Future<String?> signedUrl(String bucket, String? key, {int seconds = 3600, bool download = false}) async => null;
  @override
  Future<List<Json>> cloudFolders(String? parentId) async => const [];
  @override
  Future<List<Json>> cloudFiles(String? folderId) async => const [];

  // ---------- UPI proof ----------
  final proofs = <List<String>>[];
  String? proofError;
  @override
  Future<Json> submitPaymentProof(String reference, String utr, {String? screenshotKey}) async {
    proofs.add([reference, utr]);
    return proofError == null ? {'status': 'review', 'reference': reference} : {'status': 'error', 'error': proofError};
  }

  // ---------- play integrity ----------
  bool playVerified = false;
  @override
  Future<String> playChallenge() async => 'nonce-1';
  @override
  Future<bool> playVerify(String token, String nonce) async => playVerified = true;
}

class FakePlay extends PlayIntegrity {
  const FakePlay();
  @override
  Future<String> token(String nonce) async => 'integrity-token';
}

Future<AppController> makeController(FakeApi api, {UpiLauncher? upi, PlayIntegrity? play}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final c = AppController(api: api, prefs: prefs, upi: upi ?? FakeUpi(const UpiLaunch()), realtime: false, play: play ?? const FakePlay());
  await c.refresh();
  return c;
}

Future<AppController> pumpApp(WidgetTester t, FakeApi api, Widget home,
    {UpiLauncher? upi, PlayIntegrity? play, double width = 400, double height = 860, double textScale = 1}) async {
  t.view.physicalSize = Size(width * 3, height * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  t.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  final c = await makeController(api, upi: upi, play: play);
  await t.pumpWidget(SkyKeepApp(controller: c, home: home, googleFonts: false));
  await t.pumpAndSettle();
  return c;
}
