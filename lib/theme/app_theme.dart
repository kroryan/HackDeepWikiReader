import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Port of HackDeepWiki's "Cyberpunk Hacker" design tokens
/// (deepwiki-open's src/app/globals.css :root / html[data-theme='dark']).
/// Keep these two palettes in sync with that file if the web app's theme
/// ever changes -- the color values are copied verbatim, not derived.
class AppColors extends ThemeExtension<AppColors> {
  final Color background;
  final Color foreground;
  final Color accentPrimary;
  final Color accentSecondary;
  final Color borderColor;
  final Color sidebarBg;
  final Color contentBg;
  final Color cardBg;
  final Color inputBg;
  final Color highlight;
  final Color muted;
  final Color linkColor;

  const AppColors({
    required this.background,
    required this.foreground,
    required this.accentPrimary,
    required this.accentSecondary,
    required this.borderColor,
    required this.sidebarBg,
    required this.contentBg,
    required this.cardBg,
    required this.inputBg,
    required this.highlight,
    required this.muted,
    required this.linkColor,
  });

  static const light = AppColors(
    background: Color(0xFFF0F4F8),
    foreground: Color(0xFF0D1117),
    accentPrimary: Color(0xFF4F46E5),
    accentSecondary: Color(0xFF06B6D4),
    borderColor: Color(0x334F46E5), // rgba(79,70,229,0.2)
    sidebarBg: Color(0xEBF8FAFC),
    contentBg: Color(0xF7FFFFFF),
    cardBg: Color(0xFAFFFFFF),
    inputBg: Color(0xE6F1F5F9),
    highlight: Color(0xFFF43F5E),
    muted: Color(0xFF64748B),
    linkColor: Color(0xFF4338CA),
  );

  static const dark = AppColors(
    background: Color(0xFF030712),
    foreground: Color(0xFFE2E8F0),
    accentPrimary: Color(0xFF00F0FF),
    accentSecondary: Color(0xFFFF007F),
    borderColor: Color(0x2600F0FF), // rgba(0,240,255,0.15)
    sidebarBg: Color(0xEB090D16),
    contentBg: Color(0xF5060910),
    cardBg: Color(0xF7070B14),
    inputBg: Color(0x0DFFFFFF),
    highlight: Color(0xFF00FF66),
    muted: Color(0xFF64748B),
    linkColor: Color(0xFF38BDF8),
  );

  @override
  AppColors copyWith({
    Color? background,
    Color? foreground,
    Color? accentPrimary,
    Color? accentSecondary,
    Color? borderColor,
    Color? sidebarBg,
    Color? contentBg,
    Color? cardBg,
    Color? inputBg,
    Color? highlight,
    Color? muted,
    Color? linkColor,
  }) {
    return AppColors(
      background: background ?? this.background,
      foreground: foreground ?? this.foreground,
      accentPrimary: accentPrimary ?? this.accentPrimary,
      accentSecondary: accentSecondary ?? this.accentSecondary,
      borderColor: borderColor ?? this.borderColor,
      sidebarBg: sidebarBg ?? this.sidebarBg,
      contentBg: contentBg ?? this.contentBg,
      cardBg: cardBg ?? this.cardBg,
      inputBg: inputBg ?? this.inputBg,
      highlight: highlight ?? this.highlight,
      muted: muted ?? this.muted,
      linkColor: linkColor ?? this.linkColor,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      foreground: Color.lerp(foreground, other.foreground, t)!,
      accentPrimary: Color.lerp(accentPrimary, other.accentPrimary, t)!,
      accentSecondary: Color.lerp(accentSecondary, other.accentSecondary, t)!,
      borderColor: Color.lerp(borderColor, other.borderColor, t)!,
      sidebarBg: Color.lerp(sidebarBg, other.sidebarBg, t)!,
      contentBg: Color.lerp(contentBg, other.contentBg, t)!,
      cardBg: Color.lerp(cardBg, other.cardBg, t)!,
      inputBg: Color.lerp(inputBg, other.inputBg, t)!,
      highlight: Color.lerp(highlight, other.highlight, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      linkColor: Color.lerp(linkColor, other.linkColor, t)!,
    );
  }
}

/// Severity color scale -- mirrors src/components/vuln/config/colors.ts
/// (SEVERITY_COLORS), shared by both the dependency and website scan views.
class SeverityColors {
  static const critical = Color(0xFFFF3333);
  static const high = Color(0xFFEF4444);
  static const medium = Color(0xFFF59E0B);
  static const low = Color(0xFF22C55E);
  static const info = Color(0xFF64748B); // also used for 'UNKNOWN'

  static Color forSeverity(String severity) {
    switch (severity.toUpperCase()) {
      case 'CRITICAL':
        return critical;
      case 'HIGH':
        return high;
      case 'MEDIUM':
        return medium;
      case 'LOW':
        return low;
      default:
        return info;
    }
  }
}

ThemeData buildAppTheme(
  AppColors c,
  Brightness brightness, {
  String fontFamily = 'Noto Sans JP',
  double fontScale = 1.0,
}) {
  final base = brightness == Brightness.dark ? ThemeData.dark().textTheme : ThemeData.light().textTheme;
  final textTheme = GoogleFonts.getTextTheme(fontFamily, base)
      .apply(bodyColor: c.foreground, displayColor: c.foreground, fontSizeFactor: fontScale);

  return ThemeData(
    brightness: brightness,
    scaffoldBackgroundColor: c.background,
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: c.accentPrimary,
      onPrimary: brightness == Brightness.dark ? Colors.black : Colors.white,
      secondary: c.accentSecondary,
      onSecondary: brightness == Brightness.dark ? Colors.black : Colors.white,
      error: c.highlight,
      onError: Colors.white,
      surface: c.cardBg,
      onSurface: c.foreground,
    ),
    textTheme: textTheme,
    fontFamily: GoogleFonts.getFont(fontFamily).fontFamily,
    appBarTheme: AppBarTheme(
      backgroundColor: c.sidebarBg,
      foregroundColor: c.foreground,
      elevation: 0,
      titleTextStyle: textTheme.titleLarge,
    ),
    cardTheme: CardThemeData(
      color: c.cardBg,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: c.borderColor),
      ),
    ),
    dividerColor: c.borderColor,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.inputBg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: c.borderColor),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: c.accentPrimary,
        foregroundColor: brightness == Brightness.dark ? Colors.black : Colors.white,
      ),
    ),
    extensions: [c],
  );
}

/// Lets widgets read `Theme.of(context).extension<AppColors>()!` for the
/// tokens ColorScheme doesn't have a direct slot for (muted, highlight,
/// link, per-surface backgrounds) -- keeps every screen in sync with a
/// single source of truth instead of hex codes scattered through the UI.
extension AppColorsExtension on ThemeData {
  AppColors get appColors => extension<AppColors>()!;
}
