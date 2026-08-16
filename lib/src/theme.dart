import 'package:flutter/material.dart';

/// Brand palette — dark chrome shared by both Field Notes sites,
/// NetOps green for network tools, SecOps cyan for security tools.
const bg = Color(0xFF0B1320);
const surface = Color(0xFF111D2E);
const surface2 = Color(0xFF16273B);
const line = Color(0xFF23364C);
const ink = Color(0xFFEAF1F8);
const mut = Color(0xFF9FB3C8);
const netGreen = Color(0xFF10B981);
const secCyan = Color(0xFF22D3EE);
const warn = Color(0xFFF59E0B);
const bad = Color(0xFFEF4444);

const monoFallback = <String>[
  'Consolas',
  'Menlo',
  'DejaVu Sans Mono',
  'monospace'
];

TextStyle mono(
        {double size = 13, Color color = ink, FontWeight? weight}) =>
    TextStyle(
        fontFamilyFallback: monoFallback,
        fontSize: size,
        color: color,
        fontWeight: weight,
        height: 1.45);

ThemeData fieldKitTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: bg,
    colorScheme: const ColorScheme.dark(
      primary: netGreen,
      secondary: secCyan,
      surface: surface,
      error: bad,
    ),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: line),
      ),
      hintStyle: const TextStyle(color: mut),
      labelStyle: const TextStyle(color: mut),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: surface2,
      contentTextStyle: TextStyle(color: ink),
      behavior: SnackBarBehavior.floating,
      width: 200,
    ),
    dividerColor: line,
  );
}
