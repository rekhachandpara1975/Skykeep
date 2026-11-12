import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'config.dart';
import 'screens/home.dart';
import 'screens/login_sheet.dart';
import 'services/api.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  assert(Config.supabaseUrl.isNotEmpty, 'pass --dart-define=SUPABASE_URL=... and SUPABASE_PUBLISHABLE_KEY=...');
  await Supabase.initialize(url: Config.supabaseUrl, publishableKey: Config.supabaseKey);
  final prefs = await SharedPreferences.getInstance();
  final api = Api();
  try {
    await api.ensureSession(prefs);
  } catch (e) {
    debugPrint('session start failed: $e'); // offline: app still opens; retried on next launch
  }
  final app = AppController(api: api, prefs: prefs);
  unawaited(app.start());
  runApp(SkyKeepApp(controller: app));
}

class SkyKeepApp extends StatefulWidget {
  const SkyKeepApp({super.key, required this.controller, this.home, this.googleFonts = true});
  final AppController controller;
  final Widget? home;
  final bool googleFonts;
  @override
  State<SkyKeepApp> createState() => _SkyKeepAppState();
}

class _SkyKeepAppState extends State<SkyKeepApp> {
  final _nav = GlobalKey<NavigatorState>();
  StreamSubscription<AuthState>? _auth;

  @override
  void initState() {
    super.initState();
    if (widget.home == null) {
      _auth = widget.controller.api.authChanges.listen((s) {
        widget.controller.refresh();
        if (s.event == AuthChangeEvent.passwordRecovery && _nav.currentContext != null) showSetPassword(_nav.currentContext!);
      });
    }
  }

  @override
  void dispose() {
    _auth?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent));
    return AppScope(
      controller: widget.controller,
      child: MaterialApp(
        navigatorKey: _nav,
        title: Config.appName,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(googleFonts: widget.googleFonts),
        home: widget.home ?? const HomeShell(),
      ),
    );
  }
}
