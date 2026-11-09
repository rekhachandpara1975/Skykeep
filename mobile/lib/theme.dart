import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// All colours live here.
class C {
  static const background = Color(0xFF0B1020);
  static const surface = Color(0xFF121A33);
  static const surface2 = Color(0xFF1A2444);
  static const border = Color(0xFF2A3558);
  static const text = Color(0xFFF1F5F9);
  static const muted = Color(0xFFA3AECB); // 7.9:1 on background
  static const primary = Color(0xFF4F8CFF);
  static const accent = Color(0xFF8A5CFF);
  static const gold = Color(0xFFF5C451); // Premium only
  static const success = Color(0xFF34D399);
  static const warning = Color(0xFFFBBF24);
  static const danger = Color(0xFFF87171);
  static const gradient = LinearGradient(colors: [primary, accent], begin: Alignment.topLeft, end: Alignment.bottomRight);
}

ThemeData buildTheme({bool googleFonts = true}) {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: C.background,
    colorScheme: const ColorScheme.dark(
      primary: C.primary, secondary: C.accent, surface: C.surface, error: C.danger,
      onPrimary: Colors.white, onSurface: C.text, outline: C.border,
    ),
    cardTheme: CardThemeData(
      color: C.surface, elevation: 0, margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: C.border)),
    ),
    appBarTheme: const AppBarTheme(backgroundColor: C.background, foregroundColor: C.text, elevation: 0, centerTitle: false),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: C.surface, indicatorColor: C.primary.withValues(alpha: 0.2),
      labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12, color: C.text)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: C.surface2,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.border)),
    ),
    chipTheme: const ChipThemeData(backgroundColor: C.surface2, side: BorderSide(color: C.border), labelStyle: TextStyle(color: C.text)),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    dividerColor: C.border,
  );
  if (!googleFonts) return base;
  return base.copyWith(textTheme: base.textTheme.apply(fontFamily: GoogleFonts.poppins().fontFamily));
}

/// Gradient call-to-action button.
class GradientButton extends StatelessWidget {
  const GradientButton({super.key, required this.label, required this.onPressed, this.icon});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      child: Opacity(
        opacity: onPressed == null ? 0.5 : 1,
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: C.gradient, borderRadius: BorderRadius.circular(14)),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onPressed,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (icon != null) ...[Icon(icon, color: Colors.white, size: 20), const SizedBox(width: 8)],
                  Flexible(child: Text(label, textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
