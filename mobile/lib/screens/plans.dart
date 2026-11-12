import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../config.dart';
import '../services/api.dart';
import '../services/premium_web.dart';
import '../theme.dart';
import 'checkout.dart';

/// "2 Days", "1 Month", "6 Months", "1 Year", "6 Hours".
String planDuration(Json p) {
  final h = (p['duration_hours'] as num?)?.toInt();
  if (h != null && h % 24 != 0) return '$h ${h == 1 ? 'Hour' : 'Hours'}';
  final d = h != null ? h ~/ 24 : (p['duration_days'] as num? ?? 1).toInt();
  if (d % 365 == 0) return '${d ~/ 365} ${d == 365 ? 'Year' : 'Years'}';
  if (d % 30 == 0) return '${d ~/ 30} ${d == 30 ? 'Month' : 'Months'}';
  return '$d ${d == 1 ? 'Day' : 'Days'}';
}

String _num(num v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

/// "₹49.5 / day", or "₹19 / hour" for plans shorter than a day.
String planUnitPrice(Json p) {
  final price = p['price_inr'] as num? ?? 0;
  final h = (p['duration_hours'] as num?)?.toInt();
  if (h != null && h < 24) return '₹${_num(price / h)} / hour';
  final days = h != null ? h / 24 : (p['duration_days'] as num? ?? 1);
  return '₹${_num(price / days)} / day';
}

/// Native plan picker (Premium tab): perks, one row per plan, and a "Get `plan` · ₹`price`" button.
class PlanPicker extends StatefulWidget {
  const PlanPicker({super.key});
  @override
  State<PlanPicker> createState() => _PlanPickerState();
}

class _PlanPickerState extends State<PlanPicker> {
  String? _selected;
  bool _busy = false;

  static const _defaultPerks = ['2 TB storage', 'Full videos', 'Downloads'];

  String? _defaultId(List<Json> plans) {
    if (plans.isEmpty) return null;
    final popular = plans.where((p) => (p['badge'] as String? ?? '').toLowerCase() == 'popular');
    return (popular.isNotEmpty ? popular.first : plans[plans.length ~/ 2])['id'] as String;
  }

  Future<void> _buy(Json plan) async {
    setState(() => _busy = true);
    try {
      await startPurchase(context, BuyMessage(plan['id'] as String, plan['price_inr'] as num?));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.status;
    final plans = app.plans;
    if (plans.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No plans right now.', style: TextStyle(color: C.muted))));
    }
    if (!plans.any((p) => p['id'] == _selected)) _selected = _defaultId(plans);
    final plan = plans.firstWhere((p) => p['id'] == _selected);
    final free = s.freePlanIds.contains(plan['id']);
    final perks = <String>{for (final p in plans) ...((p['perks'] as List?) ?? const []).map((e) => '$e')}.toList();
    final chips = (perks.length >= 3 ? perks : _defaultPerks).take(3).toList();
    final canPay = free || s.paymentsAvailable;

    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
      if (app.pendingOrder != null) ...[
        Card(child: ListTile(
          leading: const Icon(Icons.hourglass_top, color: C.warning),
          title: Text('Payment ${app.pendingOrder!['reference']} is being checked'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentStatusScreen(orderId: app.pendingOrder!['id'] as String))),
        )),
        const SizedBox(height: 8),
      ],
      Row(children: [
        for (final c in chips) Expanded(child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: C.border)),
          child: Text(c, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontWeight: FontWeight.w600)),
        )),
      ]),
      const SizedBox(height: 20),
      const Text('Choose your plan', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      for (final p in plans)
        PlanRow(plan: p, selected: p['id'] == _selected, free: s.freePlanIds.contains(p['id']),
            onTap: () => setState(() => _selected = p['id'] as String)),
      const SizedBox(height: 8),
      GradientButton(
        label: _busy ? 'Please wait…' : 'Get ${plan['name']} · ${free ? 'Free' : '₹${_num(plan['price_inr'] as num)}'}',
        onPressed: _busy || !canPay ? null : () => _buy(plan),
      ),
      if (!canPay) const Padding(padding: EdgeInsets.only(top: 8),
          child: Text('Payments are paused right now. Please try again later.', textAlign: TextAlign.center, style: TextStyle(color: C.muted))),
      const SizedBox(height: 16),
      const PolicyLinks(),
    ]);
  }
}

class PlanRow extends StatelessWidget {
  const PlanRow({super.key, required this.plan, required this.selected, required this.onTap, this.free = false});
  final Json plan;
  final bool selected, free;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : C.text;
    final sub = selected ? const Color(0xE6FFFFFF) : C.muted;
    final badge = plan['badge'] as String?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Ink(
              decoration: BoxDecoration(
                gradient: selected ? C.gradient : null,
                color: selected ? null : C.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: selected ? C.primaryDark : C.border, width: selected ? 2 : 1),
              ),
              child: IntrinsicHeight(child: Row(children: [
                SizedBox(width: 104, child: Center(child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  child: Text(free ? 'FREE' : '₹${_num(plan['price_inr'] as num)}',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: fg)),
                ))),
                VerticalDivider(width: 1, thickness: 1, color: selected ? const Color(0x66FFFFFF) : C.border),
                Expanded(child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text('${plan['name']}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: fg)),
                      if (badge != null && badge.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: selected ? const Color(0x33FFFFFF) : C.primarySoft, borderRadius: BorderRadius.circular(20)),
                          child: Text(badge, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? Colors.white : C.primary)),
                        ),
                    ]),
                    const SizedBox(height: 4),
                    Text('${planDuration(plan)} · ${planUnitPrice(plan)}', style: TextStyle(color: sub)),
                  ]),
                )),
                if (selected) const Padding(padding: EdgeInsets.only(right: 14),
                    child: CircleAvatar(radius: 14, backgroundColor: Colors.white, child: Icon(Icons.check, size: 18, color: C.primary))),
              ])),
            ),
          ),
        ),
      ),
    );
  }
}

/// Privacy Policy · Terms & Conditions · Refund Policy (website pages).
class PolicyLinks extends StatelessWidget {
  const PolicyLinks({super.key});
  static void open(String path) => launchUrl(Uri.parse('${Config.websiteUrl}$path'), mode: LaunchMode.externalApplication);
  @override
  Widget build(BuildContext context) => Wrap(alignment: WrapAlignment.center, spacing: 4, children: [
        TextButton(onPressed: () => open('/privacy'), child: const Text('Privacy Policy')),
        TextButton(onPressed: () => open('/terms'), child: const Text('Terms & Conditions')),
        TextButton(onPressed: () => open('/refund'), child: const Text('Refund Policy')),
      ]);
}
