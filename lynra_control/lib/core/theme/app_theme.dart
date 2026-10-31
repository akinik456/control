import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_fonts.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get data => ThemeData(
    useMaterial3: true,

    brightness:
        AppColors.isDark ? Brightness.dark : Brightness.light,

    scaffoldBackgroundColor: AppColors.background,

    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness:
          AppColors.isDark ? Brightness.dark : Brightness.light,
    ).copyWith(
      primary: AppColors.primary,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.danger,
    ),

    appBarTheme: AppBarThemeData(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.primary,
      centerTitle: true,
      elevation: 0,
      titleTextStyle: AppFonts.pageTitle,
    ),
  );
}