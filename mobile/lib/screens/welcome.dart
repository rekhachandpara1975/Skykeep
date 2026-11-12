import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../config.dart';
import '../theme.dart';

/// First launch: Terms & Privacy consent, then Android's notification permission prompt.
/// Shown once per install; the guest account is already created in the background.
class WelcomeGate extends StatefulWidget {
  const WelcomeGate({super.key, required this.child});
  final Widget child;
  static const prefKey = 'terms_accepted_v1';
  static const _perm = MethodChannel('app/perm');

  /// Android 13+ shows "Allow SkyKeep to send you notifications?"; older versions allow by default.
  static Future<void> askNotifications() async {
    try {
      await _perm.invokeMethod<void>('notifications');
    } catch (_) {/* not on Android / tests */}
  }

  @override
  State<WelcomeGate> createState() => _WelcomeGateState();
}

class _WelcomeGateState extends State<WelcomeGate> {
  bool? _accepted;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _accepted ??= AppScope.read(context).prefs.getBool(WelcomeGate.prefKey) ?? false;
  }

  Future<void> _agree() async {
    await AppScope.read(context).prefs.setBool(WelcomeGate.prefKey, true);
    if (!mounted) return;
    setState(() => _accepted = true);
    await WelcomeGate.askNotifications();
  }

  @override
  Widget build(BuildContext context) => _accepted == true ? widget.child : ConsentScreen(onAgree: _agree);
}

class ConsentScreen extends StatelessWidget {
  const ConsentScreen({super.key, required this.onAgree});
  final VoidCallback onAgree;

  static void _open(String path) => launchUrl(Uri.parse('${Config.websiteUrl}$path'), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: C.heroGradient),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(20),
          child: SafeArea(child: Center(child: SingleChildScrollView(child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
            decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(28), border: Border.all(color: C.border),
                boxShadow: const [BoxShadow(color: Color(0x1A0F172A), blurRadius: 24, offset: Offset(0, 8))]),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Center(child: CloudMark(size: 84)),
              const SizedBox(height: 18),
              const Text('Terms of Service and Privacy Policy', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: C.text)),
              const SizedBox(height: 12),
              const Text(
                  'Welcome to ${Config.appName}. By using this app, you acknowledge that you understand how we collect, use and '
                  'protect your personal data, as well as your rights and responsibilities as a user. '
                  'Please review and accept our Privacy Policy and Terms & Conditions.',
                  textAlign: TextAlign.center, style: TextStyle(color: C.muted, height: 1.45)),
              Wrap(alignment: WrapAlignment.center, children: [
                TextButton(onPressed: () => _open('/privacy'), child: const Text('Privacy Policy')),
                TextButton(onPressed: () => _open('/terms'), child: const Text('Terms & Conditions')),
              ]),
              const SizedBox(height: 8),
              GradientButton(label: 'Agree and continue', onPressed: onAgree),
            ]),
          )))),
        ),
      );
}
