import 'package:flutter/material.dart';

import '../config.dart';
import '../services/status.dart';
import '../theme.dart';

class Logo extends StatelessWidget {
  const Logo({super.key, this.size = 32});
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
        label: '${Config.appName} logo',
        child: Container(
          width: size, height: size,
          decoration: BoxDecoration(gradient: C.gradient, borderRadius: BorderRadius.circular(size / 4)),
          alignment: Alignment.center,
          child: Text(Config.shortCode, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.4)),
        ),
      );
}

class Skeleton extends StatelessWidget {
  const Skeleton({super.key, this.height = 72});
  final double height;
  @override
  Widget build(BuildContext context) => Container(
        height: height,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(16)),
      );
}

class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 6});
  final int count;
  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [for (var i = 0; i < count; i++) const Skeleton()],
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 48),
          Icon(icon, size: 56, color: C.muted),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, textAlign: TextAlign.center, style: const TextStyle(color: C.muted)),
          ],
          if (action != null) ...[const SizedBox(height: 16), Center(child: action!)],
        ],
      );
}

class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.onRetry, this.message = 'Something went wrong.'});
  final VoidCallback onRetry;
  final String message;
  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.cloud_off, title: message,
        action: OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
      );
}

class StorageMeter extends StatelessWidget {
  const StorageMeter({super.key, required this.used, required this.quota});
  final int used, quota;
  @override
  Widget build(BuildContext context) {
    final pct = quota == 0 ? 0.0 : (used / quota).clamp(0.0, 1.0);
    return Semantics(
      label: 'Storage ${formatBytes(used)} of ${formatBytes(quota)} used',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.cloud, color: C.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('${formatBytes(used)} of ${formatBytes(quota)} used', style: const TextStyle(fontWeight: FontWeight.w500))),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(value: pct, minHeight: 8, backgroundColor: C.surface2,
              color: pct > 0.9 ? C.danger : C.primary),
        ),
      ]),
    );
  }
}

class PremiumBadge extends StatelessWidget {
  const PremiumBadge({super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: C.gold.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.workspace_premium, color: C.gold, size: 14),
          SizedBox(width: 4),
          Text('Premium', style: TextStyle(color: C.gold, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );
}

void toast(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(msg)));

String friendlyError(Object e) {
  final s = e.toString();
  final m = RegExp(r'message: ([^,)]+)').firstMatch(s);
  return (m?.group(1) ?? s).replaceFirst('Exception: ', '');
}
