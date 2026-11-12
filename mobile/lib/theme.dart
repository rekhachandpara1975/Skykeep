import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// All colours live here — exact SkyKeep brand tokens (docs/brand/README.md).
class C {
  // brand
  static const primary = Color(0xFF2563EB);
  static const primaryDark = Color(0xFF1D4ED8);
  static const accent = Color(0xFF38BDF8); // sky
  static const navy = Color(0xFF0B1220);
  static const navy2 = Color(0xFF111C30);
  static const darkCard = Color(0xFF17243A);
  // light surfaces
  static const background = Color(0xFFF7F9FC);
  static const surface = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFEFF4FB); // tinted fills, chips, skeletons
  static const primarySoft = Color(0xFFE6EEFD);
  static const border = Color(0xFFE2E8F0);
  static const text = Color(0xFF0F172A);
  static const muted = Color(0xFF64748B); // 4.8:1 on white
  // status (icons/fills use the token; text on white uses the darker *Text shade for contrast)
  static const success = Color(0xFF10B981);
  static const successText = Color(0xFF047857);
  static const warning = Color(0xFFF59E0B);
  static const warningText = Color(0xFFB45309);
  static const danger = Color(0xFFEF4444);
  static const dangerText = Color(0xFFB91C1C);
  static const gold = Color(0xFFF5C76A); // Premium only
  static const goldText = Color(0xFF9A6A00);
  static const folder = Color(0xFFF5C76A);
  static const gradient = LinearGradient(colors: [accent, primary], begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const heroGradient = LinearGradient(colors: [Color(0xFFDBEAFE), Color(0xFFF0F7FF)], begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const navyGradient = LinearGradient(colors: [navy2, navy], begin: Alignment.topLeft, end: Alignment.bottomRight);
}

ThemeData buildTheme({bool googleFonts = true}) {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: C.background,
    colorScheme: const ColorScheme.light(
      primary: C.primary, secondary: C.accent, surface: C.surface, error: C.danger,
      onPrimary: Colors.white, onSurface: C.text, outline: C.border, primaryContainer: C.primarySoft,
    ),
    cardTheme: CardThemeData(
      color: C.surface, elevation: 0, margin: EdgeInsets.zero, shadowColor: const Color(0x14153A80),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: C.border)),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: C.background, foregroundColor: C.text, elevation: 0, scrolledUnderElevation: 0, centerTitle: false,
      titleTextStyle: TextStyle(color: C.text, fontSize: 22, fontWeight: FontWeight.w700),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: C.surface, elevation: 0, height: 68, indicatorColor: C.primarySoft,
      surfaceTintColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? C.primary : C.muted)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(fontSize: 12,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? C.primary : C.muted)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: C.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.primary, width: 1.5)),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
      backgroundColor: C.primary, foregroundColor: Colors.white, minimumSize: const Size(64, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), textStyle: const TextStyle(fontWeight: FontWeight.w600))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
      foregroundColor: C.primary, minimumSize: const Size(64, 48), side: const BorderSide(color: C.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), textStyle: const TextStyle(fontWeight: FontWeight.w600))),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: C.primary)),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: C.primary, foregroundColor: Colors.white, shape: CircleBorder()),
    chipTheme: const ChipThemeData(backgroundColor: C.surface, selectedColor: C.primarySoft, side: BorderSide(color: C.border),
        labelStyle: TextStyle(color: C.text), shape: StadiumBorder()),
    listTileTheme: const ListTileThemeData(iconColor: C.muted),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: C.surface, surfaceTintColor: Colors.transparent),
    dialogTheme: const DialogThemeData(backgroundColor: C.surface, surfaceTintColor: Colors.transparent),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    dividerColor: C.border,
  );
  if (!googleFonts) return base;
  return base.copyWith(textTheme: base.textTheme.apply(fontFamily: GoogleFonts.inter().fontFamily));
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
          decoration: BoxDecoration(gradient: C.gradient, borderRadius: BorderRadius.circular(14),
              boxShadow: onPressed == null ? null : const [BoxShadow(color: Color(0x332563EB), blurRadius: 12, offset: Offset(0, 4))]),
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

/// Pill toggle used for Following/For You, Discover/Joined, Login/Sign up, Monthly/Yearly.
class PillTabs extends StatelessWidget {
  const PillTabs({super.key, required this.labels, required this.index, required this.onChanged});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(child: Semantics(
              selected: i == index, button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(color: i == index ? C.primary : Colors.transparent, borderRadius: BorderRadius.circular(11)),
                  child: Text(labels[i], textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w600, color: i == index ? Colors.white : C.text)),
                ),
              ),
            )),
        ]),
      );
}

/// "Categories        See All >"
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.onSeeAll});
  final String title;
  final VoidCallback? onSeeAll;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 10),
        child: Row(children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: C.text))),
          if (onSeeAll != null)
            TextButton(onPressed: onSeeAll, child: const Row(mainAxisSize: MainAxisSize.min, children: [Text('See all'), Icon(Icons.chevron_right, size: 18)])),
        ]),
      );
}

/// The SkyKeep mark: blue cloud with a white upload arrow (same as the launcher icon family).
class CloudMark extends StatelessWidget {
  const CloudMark({super.key, this.size = 32});
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size * 0.72, child: CustomPaint(painter: _CloudPainter()));
}

class _CloudPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final cloud = Path()
      ..addOval(Rect.fromCircle(center: Offset(w * .27, h * .62), radius: h * .34))
      ..addOval(Rect.fromCircle(center: Offset(w * .52, h * .44), radius: h * .44))
      ..addOval(Rect.fromCircle(center: Offset(w * .76, h * .6), radius: h * .36))
      ..addRRect(RRect.fromLTRBR(w * .27, h * .5, w * .76, h * .96, Radius.circular(h * .1)));
    canvas.drawPath(cloud, Paint()..shader = C.gradient.createShader(Offset.zero & s));
    final a = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = w * .075..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    canvas.drawLine(Offset(w * .52, h * .82), Offset(w * .52, h * .42), a);
    canvas.drawPath(Path()..moveTo(w * .4, h * .55)..lineTo(w * .52, h * .4)..lineTo(w * .64, h * .55), a);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
