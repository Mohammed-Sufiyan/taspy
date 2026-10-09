import 'package:flutter/material.dart';

/// "Midnight lime" brand palette. The app is dark-only by design.
abstract final class TapsyColors {
  static const lime = Color(0xFFC6FF3D);
  static const limeDeep = Color(0xFF7FA81F); // 3D edge of lime buttons
  static const onLime = Color(0xFF1A2E05);

  static const background = Color(0xFF09090B);
  static const surface = Color(0xFF131316);
  static const surfaceHigh = Color(0xFF1C1C21);
  static const outline = Color(0xFF2A2A31);

  static const text = Color(0xFFF4F4F5);
  static const textMuted = Color(0xFFA1A1AA);
  static const textFaint = Color(0xFF71717A);

  static const danger = Color(0xFFFF5C5C);
  static const warning = Color(0xFFFFB547);
}

abstract final class AppTheme {
  static const fontFamily = 'Sora';

  static final dark = _build();

  static ThemeData _build() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: TapsyColors.lime,
      onPrimary: TapsyColors.onLime,
      primaryContainer: Color(0xFF2C3A0E),
      onPrimaryContainer: TapsyColors.lime,
      secondary: Color(0xFFE4E4E7),
      onSecondary: TapsyColors.background,
      secondaryContainer: TapsyColors.surfaceHigh,
      onSecondaryContainer: TapsyColors.text,
      tertiary: Color(0xFF8B9CFF),
      onTertiary: Color(0xFF0B1033),
      tertiaryContainer: Color(0xFF1E2350),
      onTertiaryContainer: Color(0xFFD6DCFF),
      error: TapsyColors.danger,
      onError: Color(0xFF2D0505),
      errorContainer: Color(0xFF3A1214),
      onErrorContainer: Color(0xFFFFC9C9),
      surface: TapsyColors.background,
      onSurface: TapsyColors.text,
      onSurfaceVariant: TapsyColors.textMuted,
      surfaceContainerLowest: TapsyColors.background,
      surfaceContainerLow: Color(0xFF0F0F12),
      surfaceContainer: TapsyColors.surface,
      surfaceContainerHigh: TapsyColors.surfaceHigh,
      surfaceContainerHighest: Color(0xFF26262C),
      outline: Color(0xFF3F3F46),
      outlineVariant: TapsyColors.outline,
      inverseSurface: TapsyColors.text,
      onInverseSurface: TapsyColors.background,
      inversePrimary: TapsyColors.limeDeep,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: TapsyColors.background,
    );
    final text = base.textTheme.apply(
      bodyColor: TapsyColors.text,
      displayColor: TapsyColors.text,
    );

    return base.copyWith(
      textTheme: text.copyWith(
        displaySmall: text.displaySmall?.copyWith(fontWeight: FontWeight.w800),
        headlineMedium: text.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        headlineSmall: text.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        bodySmall: text.bodySmall?.copyWith(color: TapsyColors.textMuted),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: TapsyColors.text,
        ),
      ),
      cardTheme: CardThemeData(
        color: TapsyColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: TapsyColors.outline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: TapsyColors.surface,
        labelStyle: const TextStyle(color: TapsyColors.textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: TapsyColors.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: TapsyColors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: TapsyColors.lime, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: TapsyColors.text,
          side: const BorderSide(color: TapsyColors.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? TapsyColors.onLime
              : TapsyColors.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? TapsyColors.lime
              : TapsyColors.surfaceHigh,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: TapsyColors.surfaceHigh,
        contentTextStyle: const TextStyle(
          fontFamily: fontFamily,
          color: TapsyColors.text,
        ),
        actionTextColor: TapsyColors.lime,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: TapsyColors.surfaceHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: TapsyColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      dividerTheme: const DividerThemeData(color: TapsyColors.outline),
      listTileTheme: const ListTileThemeData(iconColor: TapsyColors.textMuted),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
