import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../config.dart';
import '../services/status.dart';
import '../theme.dart';
import '../version.dart';
import '../widgets/common.dart';
import 'channels.dart';
import 'home.dart' show HomeShellState;
import 'checkout.dart';
import 'login_sheet.dart';
import 'premium.dart';

/// Round avatar in the top-right corner of every tab → opens the Profile page.
class ProfileButton extends StatelessWidget {
  const ProfileButton({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final name = app.api.isGuest ? null : (app.status.displayName ?? app.api.user?.email);
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: IconButton(
        tooltip: 'Profile',
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
        icon: CircleAvatar(radius: 17, backgroundColor: C.primarySoft,
            child: name == null || name.isEmpty
                ? const Icon(Icons.person, color: C.primary, size: 20)
                : Text(name.substring(0, 1).toUpperCase(), style: const TextStyle(color: C.primary, fontWeight: FontWeight.w700))),
      ),
    );
  }
}

/// Profile page: account card, "Link your email" (guests), Go Premium / My cloud, payment history, my channels.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.status;
    final guest = app.api.isGuest;
    final sellsHere = Config.sellsPlans && !s.freeMode && s.plansVisible;
    void openPremium() => Navigator.push(context, MaterialPageRoute(builder: (_) => const PremiumScreen()));
    void openCloud() {
      Navigator.popUntil(context, (r) => r.isFirst);
      HomeShellState.current?.go(HomeShellState.cloudTab);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Profile'), actions: [
        IconButton(tooltip: 'Settings', icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
        const SizedBox(width: 4),
      ]),
      body: RefreshIndicator(
        onRefresh: app.refresh,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          AccountCard(status: s, isGuest: guest),
          if (guest) ...[
            const SizedBox(height: 12),
            Material(
              color: C.primarySoft,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => requireMember(context, reason: 'Keep your plan and files if you change phones', signUp: true),
                child: const Padding(padding: EdgeInsets.all(16), child: Row(children: [
                  Icon(Icons.mail_outline, color: C.primary),
                  SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Link your email', style: TextStyle(fontWeight: FontWeight.w700, color: C.primary)),
                    Text('Keep your plan and files if you change phones', style: TextStyle(color: C.text)),
                  ])),
                  Icon(Icons.chevron_right, color: C.primary),
                ])),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(children: [
            if (sellsHere || s.hasPlan) ...[
              Expanded(child: _Tile(
                icon: Icons.workspace_premium, label: s.hasPlan ? 'My plan' : 'Go Premium', highlighted: !s.hasPlan, onTap: openPremium)),
              const SizedBox(width: 12),
            ],
            Expanded(child: _Tile(icon: Icons.cloud_outlined, label: 'My cloud', onTap: openCloud)),
          ]),
          if (s.hasPlan || sellsHere) ...[
            const SizedBox(height: 12),
            Card(child: ListTile(
              leading: const Icon(Icons.receipt_long, color: C.primary),
              title: const Text('Payment history'),
              subtitle: const Text('Your plans and receipts'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaymentHistoryScreen())),
            )),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 4),
            child: Row(children: [
              const Expanded(child: Text('My Channels', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
              TextButton(onPressed: () => openChannelForm(context), child: const Text('Add Channel')),
            ]),
          ),
          Card(child: ListTile(
            leading: const Icon(Icons.hub_outlined, color: C.primary),
            title: const Text('See my channels'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('My channels')), body: const ChannelList(tab: 'mine')))),
          )),
        ]),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.label, required this.onTap, this.highlighted = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;
  @override
  Widget build(BuildContext context) => Material(
        color: highlighted ? null : C.surface,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            gradient: highlighted ? C.gradient : null,
            borderRadius: BorderRadius.circular(20),
            border: highlighted ? null : Border.all(color: C.border),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, color: highlighted ? Colors.white : C.primary, size: 28),
                const SizedBox(height: 18),
                Text(label, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: highlighted ? Colors.white : C.text)),
              ]),
            ),
          ),
        ),
      );
}

class PremiumTile extends StatelessWidget {
  const PremiumTile({super.key});
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(gradient: C.navyGradient, borderRadius: BorderRadius.circular(16)),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: const Icon(Icons.workspace_premium, color: C.gold, size: 36),
          title: const Text('Go Premium', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          subtitle: const Text('2 TB storage · full videos · downloads', style: TextStyle(color: Color(0xFFCBD5E1))),
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
      planLine = '${status.planName ?? 'Premium'} active until ${formatPlanEnd(status.planEndsAt)}';
    } else if (status.freeMode && status.isOrganic) {
      planLine = switch (status.accessStatus) { 'approved' => 'Full access', 'pending' => 'Full access requested', _ => 'Free account' };
    } else if (status.freeMode) {
      planLine = 'Full access';
    } else {
      planLine = 'Free account';
    }
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        CircleAvatar(radius: 30, backgroundColor: C.primarySoft, child: Text((status.displayName ?? email ?? 'G').substring(0, 1).toUpperCase(),
            style: const TextStyle(fontSize: 24, color: C.primary, fontWeight: FontWeight.w700))),
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
    Widget policy(String title, String path) => Material(
          color: C.surface,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => launchUrl(Uri.parse('${Config.websiteUrl}$path'), mode: LaunchMode.externalApplication),
            child: Ink(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: C.border)),
              child: Center(child: Padding(padding: const EdgeInsets.all(12),
                  child: Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)))),
            ),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(child: CustomScrollView(slivers: [SliverFillRemaining(hasScrollBody: false, child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 2.6,
            children: [
              policy('Privacy Policy', '/privacy'),
              policy('Terms & Conditions', '/terms'),
              policy('Community Guidelines', '/terms#community'),
              policy('Refund Policy', '/refund'),
            ],
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: () => launchUrl(Uri.parse('mailto:${Config.supportEmail}')), child: const Text('Contact support')),
          TextButton(onPressed: () => launchUrl(Uri.parse('${Config.websiteUrl}/report-content'), mode: LaunchMode.externalApplication),
              child: const Text('Report content')),
          const Spacer(),
          const SizedBox(height: 16),
          if (!app.api.isGuest)
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () async {
                await app.api.signOut();
                await app.refresh();
                if (context.mounted) Navigator.popUntil(context, (r) => r.isFirst);
              },
              child: const Text('Logout'),
            ),
          const SizedBox(height: 12),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), foregroundColor: C.dangerText),
            onPressed: () => _delete(context),
            child: const Text('Delete Account'),
          ),
          const SizedBox(height: 8),
          const Center(child: Text('Version $appVersion', key: Key('version-label'), style: TextStyle(color: C.muted, fontSize: 12))),
        ]),
      ))])),
    );
  }
}
