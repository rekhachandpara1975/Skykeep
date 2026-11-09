import 'package:flutter/material.dart';

import '../app_state.dart';
import '../config.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Returns true when the user is a member (logged in) after the sheet closes.
Future<bool> requireMember(BuildContext context, {String reason = 'Log in to continue'}) async {
  final app = AppScope.read(context);
  if (!app.api.isGuest) return true;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => LoginSheet(reason: reason),
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
  const LoginSheet({super.key, required this.reason});
  final String reason;
  @override
  State<LoginSheet> createState() => _LoginSheetState();
}

class _LoginSheetState extends State<LoginSheet> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUp = true, _busy = false;
  String? _error, _info;

  Future<void> _run(Future<void> Function() f, {String? info, bool close = false}) async {
    setState(() { _busy = true; _error = null; _info = null; });
    try {
      await f();
      if (close && mounted) return Navigator.pop(context);
      setState(() => _info = info);
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = AppScope.read(context).api;
    final valid = _email.text.contains('@') && (_password.text.length >= 8);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [const Logo(), const SizedBox(width: 12), Expanded(child: Text(widget.reason, style: Theme.of(context).textTheme.titleMedium))]),
          const SizedBox(height: 8),
          Text(_signUp ? 'Create a free account. Everything you did as a guest stays.' : 'Welcome back.', style: const TextStyle(color: C.muted)),
          const SizedBox(height: 16),
          TextField(controller: _email, keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Email'), onChanged: (_) => setState(() {})),
          const SizedBox(height: 12),
          TextField(controller: _password, obscureText: true,
              autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
              decoration: const InputDecoration(labelText: 'Password (8+ characters)'), onChanged: (_) => setState(() {})),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: C.danger))),
          if (_info != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_info!, style: const TextStyle(color: C.success))),
          const SizedBox(height: 16),
          GradientButton(
            label: _busy ? 'Please wait…' : (_signUp ? 'Create account' : 'Log in'),
            onPressed: _busy || !valid ? null : () => _signUp
                ? _run(() => api.signUp(_email.text.trim(), _password.text), info: 'Check your email to confirm, then come back.')
                : _run(() => api.signIn(_email.text.trim(), _password.text), close: true),
          ),
          TextButton(onPressed: () => setState(() => _signUp = !_signUp),
              child: Text(_signUp ? 'I already have an account' : 'Create a new account')),
          if (!_signUp)
            TextButton(
              onPressed: _busy || !_email.text.contains('@') ? null
                  : () => _run(() => api.resetPassword(_email.text.trim()), info: 'Password reset link sent. Open it on this phone.'),
              child: const Text('Forgot password?'),
            ),
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
