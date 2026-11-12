import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app_state.dart';
import '../config.dart';
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
