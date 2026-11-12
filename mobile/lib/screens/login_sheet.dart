import 'package:flutter/material.dart';

import '../app_state.dart';
import '../config.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Returns true when the user is a member (logged in) after the sheet closes.
Future<bool> requireMember(BuildContext context, {String reason = 'Log in to continue', bool signUp = false}) async {
  final app = AppScope.read(context);
  if (!app.api.isGuest) return true;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => LoginSheet(reason: reason, signUp: signUp),
  );
  await app.refresh();
  return !app.api.isGuest;
}

/// Community rules before the first upload/post.
Future<bool> requireConsent(BuildContext context) async {
  final api = AppScope.read(context).api;
  if (await api.hasConsent()) return true;
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Community rules'),
      content: const SingleChildScrollView(
        child: Text('Before you post:\n\n'
            '• No sexual or nude content, and nothing involving minors — ever.\n'
            '• No violence, hate, harassment, scams or spam.\n'
            '• Only upload what you own or have rights to.\n'
            '• We review channels and remove content that breaks these rules.\n\n'
            'Full rules: ${Config.websiteUrl}/terms#community'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('I agree')),
      ],
    ),
  );
  if (ok != true) return false;
  await api.giveConsent();
  return true;
}

class LoginSheet extends StatefulWidget {
  const LoginSheet({super.key, required this.reason, this.signUp = false});
  final String reason;
  final bool signUp;
  @override
  State<LoginSheet> createState() => _LoginSheetState();
}

class _LoginSheetState extends State<LoginSheet> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  late bool _signUp = widget.signUp;
  bool _busy = false;
  String? _error, _info;

  Future<void> _run(Future<void> Function() f, {String? info, bool close = false}) async {
    setState(() { _busy = true; _error = null; _info = null; });
    try {
      await f();
      if (!mounted) return;
      if (close) return Navigator.pop(context);
      setState(() => _info = info);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _show = false;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    final api = app.api;
    final valid = _email.text.contains('@') && (_password.text.length >= 8);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: C.border, borderRadius: BorderRadius.circular(4)))),
          const SizedBox(height: 16),
          const Center(child: CloudMark(size: 56)),
          const SizedBox(height: 8),
          Text(_signUp ? 'Create account' : 'Log in', textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(widget.reason, textAlign: TextAlign.center, style: const TextStyle(color: C.muted)),
          const SizedBox(height: 16),
          PillTabs(labels: const ['Log in', 'Create account'], index: _signUp ? 1 : 0,
              onChanged: (i) => setState(() { _signUp = i == 1; _error = null; _info = null; })),
          const SizedBox(height: 16),
          TextField(controller: _email, keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Email', hintText: 'you@example.com', prefixIcon: Icon(Icons.mail_outline)),
              onChanged: (_) => setState(() {})),
          const SizedBox(height: 12),
          TextField(controller: _password, obscureText: !_show,
              autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
              decoration: InputDecoration(labelText: 'Password (8+ characters)', prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(tooltip: _show ? 'Hide password' : 'Show password',
                      icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined), onPressed: () => setState(() => _show = !_show))),
              onChanged: (_) => setState(() {})),
          if (!_signUp)
            Align(alignment: Alignment.centerRight, child: TextButton(
              onPressed: _busy || !_email.text.contains('@') ? null
                  : () => _run(() => api.resetPassword(_email.text.trim()), info: 'Password reset link sent. Open it on this phone.'),
              child: const Text('Forgot password?'),
            )),
          if (_signUp) const Padding(padding: EdgeInsets.only(top: 8),
              child: Text('Your plan, files and channels from this phone stay with your account.', style: TextStyle(color: C.muted, fontSize: 13))),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: C.dangerText))),
          if (_info != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_info!, style: const TextStyle(color: C.successText))),
          const SizedBox(height: 16),
          GradientButton(
            label: _busy ? 'Please wait…' : (_signUp ? 'Create account' : 'Log in'),
            onPressed: _busy || !valid ? null : () => _signUp
                ? _run(() async {
                    await api.signUp(_email.text.trim(), _password.text);
                    await app.refresh();
                    if (!api.isGuest && mounted) Navigator.pop(context); // account ready at once
                  }, info: 'Check your email to confirm, then come back.')
                : _run(() => api.signIn(_email.text.trim(), _password.text), close: true),
          ),
          const SizedBox(height: 4),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Not now')),
        ]),
      ),
    );
  }
}

/// After a password-recovery link opens the app.
Future<void> showSetPassword(BuildContext context) async {
  final c = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Set a new password'),
      content: TextField(controller: c, obscureText: true, decoration: const InputDecoration(labelText: 'New password')),
      actions: [
        FilledButton(
          onPressed: () async {
            if (c.text.length < 8) return;
            await AppScope.read(context).api.setPassword(c.text);
            if (d.mounted) Navigator.pop(d);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
