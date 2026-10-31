import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppFonts {
  AppFonts._();

  static TextStyle get title => TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        height: 1.2,
      );

  static TextStyle get subtitle => TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        height: 1.3,
      );

  static TextStyle get body => TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
        height: 1.45,
      );

  static TextStyle get caption => TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
        height: 1.4,
      );

  static TextStyle get button => TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      );
			
	static TextStyle get pageTitle => TextStyle(
		fontSize: 22,
		fontWeight: FontWeight.w600,
		color: AppColors.primary,
		height: 1.3,
	);		
}