import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static bool isDark = true;

  static Color get background =>
      isDark ? const Color(0xFF020617) : const Color(0xFFF8FAFC);

  static Color get surface =>
      isDark ? const Color(0xFF0F172A) : const Color(0xFFFFFFFF);

  static Color get card =>
      isDark ? const Color(0xFF111827) : const Color(0xFFF1F5F9);

  static Color get primary =>
      isDark ? const Color(0xFF22D3EE) : const Color(0xFF0891B2);

  static Color get accent =>
      isDark ? const Color(0xFF14B8A6) : const Color(0xFF0F766E);

  static Color get textPrimary =>
      isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A);

  static Color get textSecondary =>
      isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

  static Color get border =>
      isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);

  static Color get danger =>
      isDark ? const Color(0xFFEF4444) : const Color(0xFFDC2626);

  static Color get success =>
      isDark ? const Color(0xFF22C55E) : const Color(0xFF16A34A);

  static Color get warning =>
      isDark ? const Color(0xFFF59E0B) : const Color(0xFFD97706);
}