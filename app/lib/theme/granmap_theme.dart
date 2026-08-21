import 'package:flutter/material.dart';

/// Tokens visuais extraídos do protótipo Figma do GranMap.
abstract final class GranMapColors {
  static const ink = Color(0xFF050C17);
  static const inkSoft = Color(0xFF091525);
  static const navy = Color(0xFF0D1B2E);
  static const navyRaised = Color(0xFF10223A);
  static const orange = Color(0xFFFF6B00);
  static const orangeLight = Color(0xFFFF812E);
  static const violet = Color(0xFF7657F6);
  static const violetDark = Color(0xFF102846);
  static const coral = orange;
  static const mint = Color(0xFF19C79A);
  static const sky = Color(0xFF2F80FF);
  static const amber = Color(0xFFF5A623);
  static const canvas = ink;
  static const card = inkSoft;
  static const line = Color(0xFF1A2C44);
  static const textMuted = Color(0xFF7084A3);
  static const danger = Color(0xFFFF525D);
}

abstract final class GranMapTheme {
  static ThemeData get light => dark;

  static ThemeData get dark {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: GranMapColors.orange,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFF3A1B0A),
      onPrimaryContainer: Color(0xFFFFD9C2),
      secondary: GranMapColors.sky,
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFF102B50),
      onSecondaryContainer: Color(0xFFD6E8FF),
      tertiary: GranMapColors.mint,
      onTertiary: Color(0xFF002D22),
      tertiaryContainer: Color(0xFF0A3B32),
      onTertiaryContainer: Color(0xFFC6FFF0),
      error: GranMapColors.danger,
      onError: Colors.white,
      errorContainer: Color(0xFF3B151D),
      onErrorContainer: Color(0xFFFFD9DD),
      surface: GranMapColors.inkSoft,
      onSurface: Color(0xFFF7FAFF),
      surfaceContainerHighest: GranMapColors.navyRaised,
      onSurfaceVariant: GranMapColors.textMuted,
      outline: Color(0xFF334966),
      outlineVariant: GranMapColors.line,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: Color(0xFFF2F6FC),
      onInverseSurface: GranMapColors.ink,
      inversePrimary: Color(0xFFB84400),
    );
    return _build(scheme);
  }

  static ThemeData _build(ColorScheme scheme) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: GranMapColors.ink,
      canvasColor: GranMapColors.ink,
    );
    final text = base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -1.25,
      ),
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -1,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -.8,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -.55,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -.35,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -.15,
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      labelSmall: base.textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.35),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.35),
    );

    return base.copyWith(
      textTheme: text,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: GranMapColors.ink,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.titleMedium?.copyWith(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: GranMapColors.inkSoft,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: GranMapColors.line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: GranMapColors.navy,
        hintStyle: const TextStyle(color: GranMapColors.textMuted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 14,
        ),
        prefixIconColor: GranMapColors.textMuted,
        suffixIconColor: GranMapColors.textMuted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: GranMapColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: GranMapColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: GranMapColors.orange, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: GranMapColors.danger),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          backgroundColor: GranMapColors.orange,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          foregroundColor: scheme.onSurface,
          side: const BorderSide(color: GranMapColors.line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: GranMapColors.orange,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: text.labelLarge,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: GranMapColors.navy,
        selectedColor: GranMapColors.orange,
        side: const BorderSide(color: GranMapColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
        labelStyle: text.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      ),
      dividerTheme: const DividerThemeData(color: GranMapColors.line, space: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: GranMapColors.mint,
        linearTrackColor: GranMapColors.navyRaised,
        linearMinHeight: 4,
        borderRadius: BorderRadius.circular(99),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: GranMapColors.inkSoft,
        indicatorColor: GranMapColors.orange.withValues(alpha: .14),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: GranMapColors.navyRaised,
        contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _GranMapPageTransitionBuilder(),
          TargetPlatform.iOS: _GranMapPageTransitionBuilder(),
          TargetPlatform.windows: _GranMapPageTransitionBuilder(),
          TargetPlatform.macOS: _GranMapPageTransitionBuilder(),
          TargetPlatform.linux: _GranMapPageTransitionBuilder(),
        },
      ),
    );
  }
}

class _GranMapPageTransitionBuilder extends PageTransitionsBuilder {
  const _GranMapPageTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curve = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, .018),
          end: Offset.zero,
        ).animate(curve),
        child: child,
      ),
    );
  }
}
