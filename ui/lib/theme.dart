import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ─── 颜色系统 ─────────────────────────────────────────────────────────────────

class AppColors {
  // 基底
  static const Color bgDeep = Color(0xFF0D0D0D);
  static const Color bgPanel = Color(0xFF141418);
  static const Color bgCard = Color(0xFF1A1A22);
  static const Color bgCardHover = Color(0xFF22222E);
  static const Color bgConsole = Color(0xFF0A0A0E);

  // 强调
  static const Color amber = Color(0xFFF0A500);
  static const Color amberDim = Color(0xFF8B6914);
  static const Color amberGlow = Color(0x40F0A500);

  // 状态
  static const Color ledGreen = Color(0xFF00E5A0);
  static const Color ledRed = Color(0xFFFF4C6A);
  static const Color ledBlue = Color(0xFF3B82F6);

  // 文字
  static const Color textPrimary = Color(0xFFE8E6E1);
  static const Color textSecondary = Color(0xFF8A8880);
  static const Color textMuted = Color(0xFF56554F);

  // 边框
  static const Color borderSubtle = Color(0xFF2A2A30);
  static const Color borderActive = Color(0xFF3A3A42);
}

/// ─── 主题构建 ─────────────────────────────────────────────────────────────────

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bgDeep,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.amber,
        secondary: AppColors.ledGreen,
        surface: AppColors.bgCard,
        error: AppColors.ledRed,
      ),
      textTheme: _textTheme,
      cardTheme: const CardThemeData(
        color: AppColors.bgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
          side: BorderSide(color: AppColors.borderSubtle, width: 1),
        ),
      ),
      dividerColor: AppColors.borderSubtle,
      iconTheme: const IconThemeData(color: AppColors.textSecondary),
      useMaterial3: true,
    );
  }

  static TextTheme get _textTheme {
    return TextTheme(
      // 标题 — JetBrains Mono
      displayLarge: GoogleFonts.jetBrainsMono(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        letterSpacing: -0.5,
      ),
      headlineMedium: GoogleFonts.jetBrainsMono(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        letterSpacing: 0.5,
      ),
      headlineSmall: GoogleFonts.jetBrainsMono(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.amber,
        letterSpacing: 1.5,
      ),
      // 正文 — DM Sans
      bodyLarge: GoogleFonts.dmSans(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimary,
      ),
      bodyMedium: GoogleFonts.dmSans(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
      ),
      bodySmall: GoogleFonts.dmSans(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: AppColors.textMuted,
      ),
      // 标签
      labelLarge: GoogleFonts.dmSans(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        letterSpacing: 0.8,
      ),
      labelMedium: GoogleFonts.jetBrainsMono(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: AppColors.textMuted,
        letterSpacing: 1.0,
      ),
    );
  }
}

/// ─── 装饰器 ─────────────────────────────────────────────────────────────────

class AppDecorations {
  static BoxDecoration get panelDecoration => BoxDecoration(
    color: AppColors.bgCard,
    borderRadius: BorderRadius.circular(4),
    border: Border.all(color: AppColors.borderSubtle, width: 1),
  );

  static BoxDecoration get consoleBg => BoxDecoration(
    color: AppColors.bgConsole,
    borderRadius: BorderRadius.circular(4),
    border: Border.all(color: AppColors.borderSubtle, width: 1),
  );

  static BoxDecoration get headerBar => const BoxDecoration(
    color: AppColors.bgPanel,
    border: Border(
      bottom: BorderSide(color: AppColors.borderSubtle, width: 1),
    ),
  );

  /// 琥珀金光晕阴影
  static List<BoxShadow> get amberGlow => const [
    BoxShadow(
      color: AppColors.amberGlow,
      blurRadius: 20,
      spreadRadius: -4,
    ),
  ];
}
