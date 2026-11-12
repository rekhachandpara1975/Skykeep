/// What the server says about the current user (my_status + plan_offers). The app never decides access itself.
class AppStatus {
  const AppStatus({
    this.userId,
    this.isGuest = true,
    this.isAdmin = false,
    this.source = 'organic',
    this.hasAdsAccess = false,
    this.isPremium = false,
    this.hasPlan = false,
    this.planName,
    this.planEndsAt,
    this.usedBytes = 0,
    this.quotaBytes = 0,
    this.freeMode = false,
    this.paidEnabled = true,
    this.accessStatus = 'none',
    this.paymentsAvailable = false,
    this.plansVisible = false,
    this.playVerified = false,
    this.playBillingEnabled = false,
    this.freePlanIds = const [],
    this.displayName,
    this.avatarUrl,
    this.loaded = false,
  });

  final String? userId;
  final bool isGuest, isAdmin, hasAdsAccess, isPremium, hasPlan;
  final String source, accessStatus;
  final String? planName, displayName, avatarUrl;
  final DateTime? planEndsAt;
  final int usedBytes, quotaBytes;
  final bool freeMode, paidEnabled, paymentsAvailable, plansVisible, playVerified, playBillingEnabled, loaded;
  final List<String> freePlanIds;

  bool get isOrganic => source == 'organic';

  factory AppStatus.fromServer(Map<String, dynamic> s, Map<String, dynamic>? offers) => AppStatus(
        userId: s['user_id'] as String?,
        isGuest: s['is_guest'] as bool? ?? true,
        isAdmin: s['is_admin'] as bool? ?? false,
        source: s['source'] as String? ?? 'organic',
        hasAdsAccess: s['has_ads_access'] as bool? ?? false,
        isPremium: s['is_premium'] as bool? ?? false,
        hasPlan: s['has_plan'] as bool? ?? false,
        planName: s['plan_name'] as String?,
        planEndsAt: DateTime.tryParse(s['plan_ends_at']?.toString() ?? '')?.toLocal(),
        usedBytes: (s['used_bytes'] as num?)?.toInt() ?? 0,
        quotaBytes: (s['quota_bytes'] as num?)?.toInt() ?? 0,
        freeMode: s['free_mode'] as bool? ?? false,
        paidEnabled: s['paid_enabled'] as bool? ?? true,
        accessStatus: s['access_status'] as String? ?? 'none',
        paymentsAvailable: (offers?['payments_available'] ?? s['payments_available']) as bool? ?? false,
        plansVisible: (offers?['plans_visible'] ?? s['plans_visible']) as bool? ?? false,
        playVerified: s['play_verified'] as bool? ?? false,
        playBillingEnabled: s['play_billing_enabled'] as bool? ?? false,
        freePlanIds: ((offers?['free_plan_ids'] as List?) ?? const []).map((e) => e.toString()).toList(),
        displayName: s['display_name'] as String?,
        avatarUrl: s['avatar_url'] as String?,
        loaded: true,
      );
}

/// Which Premium experience this build + status should show.
enum PremiumMode { freeAccount, hidden, web }

PremiumMode premiumMode(AppStatus s, {required bool playStore}) {
  // Play Store build: never any purchase (UPI checkout only in the website / ads APKs).
  if (playStore) return PremiumMode.freeAccount;
  if (s.freeMode) return PremiumMode.freeAccount;
  if (!s.plansVisible) return PremiumMode.hidden;
  return PremiumMode.web;
}

String formatBytes(num n) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = n.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(i == 0 || v >= 100 ? 0 : 1)} ${units[i]}';
}

String formatDate(DateTime? d) {
  if (d == null) return '—';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}

/// ₹ with Indian grouping: 123456.5 → ₹1,23,456.50
String rupees(num v, {bool paise = false}) {
  final whole = v.truncate().abs().toString();
  String g;
  if (whole.length <= 3) {
    g = whole;
  } else {
    final last3 = whole.substring(whole.length - 3);
    var rest = whole.substring(0, whole.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    g = '${parts.join(',')},$last3';
  }
  final frac = ((v.abs() - v.truncate().abs()) * 100).round();
  final showFrac = paise || frac != 0;
  return '${v < 0 ? '-' : ''}₹$g${showFrac ? '.${frac.toString().padLeft(2, '0')}' : ''}';
}
