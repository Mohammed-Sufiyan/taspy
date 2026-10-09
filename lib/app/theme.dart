import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const _seed = Color(0xFF0E7C7B);

  static final light = ThemeData(colorSchemeSeed: _seed, useMaterial3: true);

  static final dark = ThemeData(
    colorSchemeSeed: _seed,
    brightness: Brightness.dark,
    useMaterial3: true,
  );
}
