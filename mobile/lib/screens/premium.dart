import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app_state.dart';
import '../config.dart';
import '../services/api.dart';
import '../services/play_billing.dart';
import '../services/premium_web.dart';
import '../services/status.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'checkout.dart';
import 'login_sheet.dart';

/// Builds the plans WebView. Tests replace it (see test/flutter_test_config.dart).
typedef PremiumWebBuilder = Widget Function(Uri url, void Function(String message) onMessage);
PremiumWebBuilder premiumWebBuilder = (url, onMessage) => PremiumWebView(url: url, onMessage: onMessage);

class PremiumScreen extends StatelessWidget {
  const PremiumScreen({super.key, this.embedded = false});
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.status;
    final mode = premiumMode(s, playStore: Config.playStore);
    final body = switch (mode) {
      PremiumMode.freeAccount => FreeAccountCard(status: s, isGuest: app.api.isGuest),
      PremiumMode.hidden => HiddenPlansView(status: s),
      PremiumMode.playBilling => PlayPlansView(status: s),
      PremiumMode.web => PremiumWeb(status: s),
    };
    if (embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text('Premium')), body: body);
  }
}

/// Free mode (or Play build while billing is off): no prices anywhere.
class FreeAccountCard extends StatelessWidget {
  const FreeAccountCard({super.key, required this.status, required this.isGuest});
  final AppStatus status;
  final bool isGuest;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Row(children: [Logo(size: 40), SizedBox(width: 12), Expanded(child: Text('Free account', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)))]),
        const SizedBox(height: 16),
        if (isGuest) ...[
          const Text('Log in to get 15 GB free cloud storage.'),
          const SizedBox(height: 12),
          GradientButton(label: 'Log in', onPressed: () => requireMember(context, reason: 'Log in to get 15 GB free')),
        ] else ...[
          StorageMeter(used: status.usedBytes, quota: status.quotaBytes),
          const SizedBox(height: 16),
          _AccessStatus(status: status, onRequest: () async {
            try {
              await app.api.requestFullAccess();
              await app.refresh();
            } catch (e) {
              if (context.mounted) toast(context, friendlyError(e));
            }
          }),
        ],
      ]))),
    ]);
  }
}

class _AccessStatus extends StatelessWidget {
  const _AccessStatus({required this.status, required this.onRequest});
  final AppStatus status;
  final VoidCallback onRequest;
  @override
  Widget build(BuildContext context) {
    if (status.isPremium || !status.isOrganic) {
      return const Row(children: [Icon(Icons.verified, color: C.success), SizedBox(width: 8), Expanded(child: Text('Full access'))]);
    }
    return switch (status.accessStatus) {
      'pending' => const Row(children: [Icon(Icons.hourglass_top, color: C.warning), SizedBox(width: 8),
          Expanded(child: Text('Full access requested — waiting for approval'))]),
      'approved' => const Row(children: [Icon(Icons.verified, color: C.success), SizedBox(width: 8), Expanded(child: Text('Full access approved'))]),
      'rejected' => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Your request was not approved.', style: TextStyle(color: C.danger)),
          TextButton(onPressed: onRequest, child: const Text('Request again')),
        ]),
      _ => OutlinedButton(onPressed: onRequest, child: const Text('Request full access')),
    };
  }
}

/// Paid mode with plans hidden: no prices or "choose a plan"; buyers still see their plan.
class HiddenPlansView extends StatelessWidget {
  const HiddenPlansView({super.key, required this.status});
  final AppStatus status;
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        if (status.hasPlan) ...[
          ActivePlanCard(status: status),
          const SizedBox(height: 12),
          ListTile(leading: const Icon(Icons.receipt_long), title: const Text('Payment history'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaymentHistoryScreen()))),
        ] else
          Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Free account', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            StorageMeter(used: status.usedBytes, quota: status.quotaBytes),
            const SizedBox(height: 12),
            const Text('Premium videos and downloads are for Premium members.', style: TextStyle(color: C.muted)),
          ]))),
      ]);
}

class ActivePlanCard extends StatelessWidget {
  const ActivePlanCard({super.key, required this.status});
  final AppStatus status;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(20), child: Row(children: [
        const Icon(Icons.workspace_premium, color: C.gold, size: 36),
        const SizedBox(width: 12),
        Expanded(child: Text('${status.planName ?? 'Premium'} active until ${formatDate(status.planEndsAt)}',
            style: const TextStyle(fontWeight: FontWeight.w600))),
      ])));
}

/// Paid mode, plans visible (direct/ads builds): website plans page in a WebView.
class PremiumWeb extends StatelessWidget {
  const PremiumWeb({super.key, required this.status});
  final AppStatus status;

  Future<void> _onMessage(BuildContext context, String raw) async {
    final msg = parseBuyMessage(raw);
    if (msg == null) return;
    await startPurchase(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final url = premiumPageUrl(freePlanIds: status.freePlanIds, paymentsAvailable: status.paymentsAvailable);
    return Column(children: [
      if (status.hasPlan)
        MaterialBanner(
          backgroundColor: C.surface2,
          leading: const Icon(Icons.workspace_premium, color: C.gold),
          content: Text('${status.planName ?? 'Premium'} active until ${formatDate(status.planEndsAt)}'),
          actions: [TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaymentHistoryScreen())), child: const Text('History'))],
        )
      else if (app.pendingOrder != null)
        MaterialBanner(
          backgroundColor: C.surface2,
          leading: const Icon(Icons.hourglass_top, color: C.warning),
          content: Text('Payment ${app.pendingOrder!['reference']} is being checked'),
          actions: [TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => PaymentStatusScreen(orderId: app.pendingOrder!['id'] as String))), child: const Text('Status'))],
        ),
      Expanded(child: premiumWebBuilder(url, (m) => _onMessage(context, m))),
    ]);
  }
}

class PremiumWebView extends StatefulWidget {
  const PremiumWebView({super.key, required this.url, required this.onMessage});
  final Uri url;
  final void Function(String) onMessage;
  @override
  State<PremiumWebView> createState() => _PremiumWebViewState();
}

class _PremiumWebViewState extends State<PremiumWebView> {
  late final WebViewController _c;
  int _progress = 0;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(C.background)
      ..addJavaScriptChannel(Config.jsChannel, onMessageReceived: (m) => widget.onMessage(m.message))
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (r) => allowWebNavigation(r.url) ? NavigationDecision.navigate : NavigationDecision.prevent,
        onProgress: (p) => setState(() => _progress = p),
        onWebResourceError: (e) { if (e.isForMainFrame ?? true) setState(() => _error = true); },
      ))
      ..loadRequest(widget.url);
  }

  @override
  void didUpdateWidget(PremiumWebView old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _c.loadRequest(widget.url);
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return ErrorRetry(message: 'Could not load plans.', onRetry: () { setState(() { _error = false; _progress = 0; }); _c.loadRequest(widget.url); });
    }
    return Stack(children: [
      WebViewWidget(controller: _c),
      if (_progress < 100) LinearProgressIndicator(value: _progress / 100),
    ]);
  }
}

/// Play build with Play billing ON (only after Google approval): plans from the server's Play catalog,
/// bought through Google Play Billing. Google's sheet shows the price and the
/// "Pay with Google Play" / "Pay with UPI" choice (User Choice Billing). No web page, no own price list.
class PlayPlansView extends StatefulWidget {
  const PlayPlansView({super.key, required this.status});
  final AppStatus status;
  @override
  State<PlayPlansView> createState() => _PlayPlansViewState();
}

class _PlayPlansViewState extends State<PlayPlansView> {
  late final AppController _app;
  late Future<List<Json>> _catalog;
  Json? _buying;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _app = AppScope.read(context);
    _catalog = _app.api.playCatalog();
    _app.play.onUserChoice = _onUserChoice;
    _app.play.onPurchases = _onPurchases;
  }

  @override
  void dispose() {
    final app = _app;
    app.play.onUserChoice = null;
    app.play.onPurchases = (r, p) => app.recordPlayPurchases(p);
    super.dispose();
  }

  Future<void> _buy(Json item) async {
    final app = _app;
    if (!await requireMember(context, reason: 'Log in to subscribe')) return;
    if (!mounted) return;
    setState(() { _busy = true; _buying = item; });
    try {
      if (await app.play.connect() != 'ready') throw Exception('Google Play billing is not available on this phone');
      final r = await app.play.buy(productId: item['product_id'] as String, basePlanId: item['base_plan_id'] as String?,
          accountId: await app.api.playAccountId());
      if (r != 'ok' && r != 'cancelled' && mounted) toast(context, r == 'already_owned' ? 'You already have this plan.' : 'Could not open Google Play');
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onPurchases(String result, List<PlayPurchase> purchases) async {
    final app = _app;
    if (result == 'cancelled') return;
    if (purchases.any((p) => p.state == 'pending') && mounted) toast(context, 'Payment pending with Google Play');
    try {
      await app.recordPlayPurchases(purchases);
      if (mounted && app.status.hasPlan) toast(context, 'Payment successful! Your plan is now active.');
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  /// Google's choice screen → "Pay with UPI": ask the buyer's state (Google needs it for tax), then the normal UPI flow.
  Future<void> _onUserChoice(String token, List<String> products) async {
    final item = _buying;
    if (item == null || !mounted) return;
    final state = await pickIndianState(context);
    if (state == null || !mounted) return;
    final app = _app;
    final plan = await app.findPlan(item['plan_id'] as String) ?? {'id': item['plan_id'], 'name': item['name']};
    if (!mounted) return;
    await upiCheckout(context, plan: plan, shownPriceInr: null,
        createOrder: () => app.api.createPlayChoiceOrder(item['plan_id'] as String, token, state));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.status;
    return FutureBuilder<List<Json>>(
      future: _catalog,
      builder: (context, snap) {
        if (snap.hasError) return ErrorRetry(message: 'Could not load plans.', onRetry: () => setState(() => _catalog = _app.api.playCatalog()));
        if (!snap.hasData) return const SkeletonList(count: 3);
        final items = snap.data!;
        if (items.isEmpty) return HiddenPlansView(status: s);
        return ListView(padding: const EdgeInsets.all(16), children: [
          if (s.hasPlan) ...[ActivePlanCard(status: s), const SizedBox(height: 12)],
          for (final item in items) Padding(padding: const EdgeInsets.only(bottom: 12), child: Card(child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const Icon(Icons.workspace_premium, color: C.gold),
                const SizedBox(width: 8),
                Expanded(child: Text(item['name'] as String? ?? 'Premium', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
                if ((item['badge'] as String?)?.isNotEmpty ?? false)
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: C.gold.withValues(alpha: .15), borderRadius: BorderRadius.circular(99)),
                      child: Text(item['badge'] as String, style: const TextStyle(color: C.gold, fontSize: 12))),
              ]),
              const SizedBox(height: 8),
              for (final perk in (item['perks'] as List? ?? const []))
                Padding(padding: const EdgeInsets.only(top: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.check, size: 18, color: C.success), const SizedBox(width: 6), Expanded(child: Text('$perk')),
                ])),
              const SizedBox(height: 16),
              GradientButton(label: _busy && _buying == item ? 'Opening Google Play…' : 'Subscribe',
                  onPressed: _busy ? null : () => _buy(item)),
            ]),
          ))),
          const Text('Price and payment options are shown by Google Play. Cancel anytime in Google Play › Subscriptions.',
              textAlign: TextAlign.center, style: TextStyle(color: C.muted, fontSize: 13)),
          const SizedBox(height: 8),
          ListTile(leading: const Icon(Icons.receipt_long), title: const Text('Payment history'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaymentHistoryScreen()))),
        ]);
      },
    );
  }
}

Future<String?> pickIndianState(BuildContext context) => showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.surface,
      builder: (c) => SafeArea(child: SizedBox(height: MediaQuery.sizeOf(c).height * .7, child: Column(children: [
        const Padding(padding: EdgeInsets.all(16), child: Text('Your state', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Google Play needs this for tax on UPI payments.', style: TextStyle(color: C.muted))),
        Expanded(child: ListView(children: [
          for (final (code, name) in indianStates) ListTile(title: Text(name), onTap: () => Navigator.pop(c, code)),
        ])),
      ]))),
    );
