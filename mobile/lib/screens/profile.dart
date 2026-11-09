import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../config.dart';
import '../services/status.dart';
import '../theme.dart';
import '../version.dart';
import '../widgets/common.dart';
import 'channels.dart';
import 'checkout.dart';
import 'login_sheet.dart';
import 'premium.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.status;
    final guest = app.api.isGuest;
    final showPlansFirst = !Config.playStore && !s.freeMode && s.plansVisible && !s.hasPlan;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: RefreshIndicator(
        onRefresh: app.refresh,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (showPlansFirst) ...[const PremiumTile(), const SizedBox(height: 12)],
          AccountCard(status: s, isGuest: guest),
          const SizedBox(height: 12),
          if (s.freeMode || Config.playStore) ...[
            SizedBox(height: 260, child: PremiumScreen(embedded: true)),
            const SizedBox(height: 12),
          ],
          Card(child: Column(children: [
            ListTile(leading: const Icon(Icons.groups), title: const Text('My channels'), trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  if (await requireMember(context, reason: 'Log in to manage channels') && context.mounted) {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('My channels')), body: const ChannelList(tab: 'mine'))));
                  }
                }),
            ListTile(leading: const Icon(Icons.upload), title: const Text('Upload content'), trailing: const Icon(Icons.chevron_right),
                onTap: () => openChannelForm(context)),
            if (!guest && (s.hasPlan || (s.plansVisible && !Config.playStore)))
              ListTile(leading: const Icon(Icons.receipt_long), title: const Text('Payment history'), trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaymentHistoryScreen()))),
            ListTile(leading: const Icon(Icons.settings), title: const Text('Settings'), trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
          ])),
        ]),
      ),
    );
  }
}

class PremiumTile extends StatelessWidget {
  const PremiumTile({super.key});
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(gradient: C.gradient, borderRadius: BorderRadius.circular(16)),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: const Icon(Icons.workspace_premium, color: C.gold, size: 36),
          title: const Text('Go Premium', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          subtitle: const Text('2 TB storage · full videos · downloads', style: TextStyle(color: Colors.white)),
          trailing: const Icon(Icons.chevron_right, color: Colors.white),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PremiumScreen())),
        ),
      );
}

class AccountCard extends StatelessWidget {
  const AccountCard({super.key, required this.status, required this.isGuest});
  final AppStatus status;
  final bool isGuest;
  @override
  Widget build(BuildContext context) {
    final email = AppScope.read(context).api.user?.email;
    final String planLine;
    if (isGuest) {
      planLine = 'Guest';
    } else if (status.hasPlan) {
      planLine = '${status.planName ?? 'Premium'} active until ${formatDate(status.planEndsAt)}';
    } else if (status.freeMode && status.isOrganic) {
      planLine = switch (status.accessStatus) { 'approved' => 'Full access', 'pending' => 'Full access requested', _ => 'Free account' };
    } else if (status.freeMode) {
      planLine = 'Full access';
    } else {
      planLine = 'Free account';
    }
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        CircleAvatar(radius: 28, backgroundColor: C.surface2, child: Text((status.displayName ?? email ?? 'G').substring(0, 1).toUpperCase(),
            style: const TextStyle(fontSize: 22, color: C.text))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(isGuest ? 'Guest' : status.displayName ?? email ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          if (!isGuest && email != null) Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted)),
          const SizedBox(height: 4),
          Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (status.isPremium && status.hasPlan) const PremiumBadge(),
            Text(planLine, style: const TextStyle(color: C.muted)),
          ]),
        ])),
      ]),
      const SizedBox(height: 16),
      if (isGuest)
        GradientButton(label: 'Log in or create account', onPressed: () => requireMember(context, reason: 'Log in to your account'))
      else
        StorageMeter(used: status.usedBytes, quota: status.quotaBytes),
    ])));
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _delete(BuildContext context) async {
    final app = AppScope.read(context);
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Delete account?'),
      content: const Text('Your account, channels and cloud files are deleted permanently. Payment records are kept for tax law without your name. This cannot be undone.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: C.danger), onPressed: () => Navigator.pop(c, true), child: const Text('Delete'))]));
    if (ok != true) return;
    try {
      await app.api.deleteAccount();
      await app.refresh();
      if (context.mounted) { toast(context, 'Account deleted'); Navigator.pop(context); }
    } catch (e) {
      if (context.mounted) toast(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    Widget link(String title, String path) => ListTile(title: Text(title), trailing: const Icon(Icons.open_in_new, size: 18),
        onTap: () => launchUrl(Uri.parse('${Config.websiteUrl}$path'), mode: LaunchMode.externalApplication));
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(children: [
        link('Privacy policy', '/privacy'),
        link('Terms, refunds & community rules', '/terms'),
        link('Report content', '/report-content'),
        ListTile(title: const Text('Contact support'), subtitle: const Text(Config.supportEmail),
            onTap: () => launchUrl(Uri.parse('mailto:${Config.supportEmail}'))),
        const Divider(),
        if (!app.api.isGuest) ...[
          ListTile(leading: const Icon(Icons.logout), title: const Text('Log out'), onTap: () async {
            await app.api.signOut();
            await app.refresh();
            if (context.mounted) Navigator.pop(context);
          }),
          ListTile(leading: const Icon(Icons.delete_forever, color: C.danger), title: const Text('Delete account', style: TextStyle(color: C.danger)),
              onTap: () => _delete(context)),
        ],
        const Divider(),
        const ListTile(title: Text('Version'), trailing: Text(appVersion, key: Key('version-label'))),
      ]),
    );
  }
}
