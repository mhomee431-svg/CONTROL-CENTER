import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Shopkeeper App theme — business-console look, mobile-first.
class AppTheme {
  AppTheme._();

  static const Color brandSeed = Color(0xFF0B5D3B); // deep commerce green
  static const Color accent = Color(0xFFF2A413);

  // Status colors
  static const Color verifiedGreen = Color(0xFF1E8E3E);
  static const Color pendingAmber = Color(0xFFB26A00);
  static const Color rejectedRed = Color(0xFFC5221F);
  static const Color suspendedGrey = Color(0xFF5F6368);

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: brandSeed,
        brightness: Brightness.light,
      ),
    );
    return base.copyWith(
      textTheme: GoogleFonts.interTextTheme(base.textTheme),
      appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
        filled: true,
      ),
      scaffoldBackgroundColor: const Color(0xFFF7F8FA),
    );
  }

  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: brandSeed,
        brightness: Brightness.dark,
      ),
    );
    return base.copyWith(textTheme: GoogleFonts.interTextTheme(base.textTheme));
  }
}
