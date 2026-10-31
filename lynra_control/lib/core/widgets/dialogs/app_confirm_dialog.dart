import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_fonts.dart';

class AppConfirmDialog {
  AppConfirmDialog._();

  static Future<bool> show({
    required BuildContext context,
    required String title,
    required String message,
    required String confirmText,
    required String cancelText,
    Color? confirmColor,
  }) async {
		final effectiveConfirmColor =
    confirmColor ?? AppColors.primary;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: Text(
            title,
            style: AppFonts.title.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          content: Text(
            message,
            style: AppFonts.body.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
              ),
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: Text(
                cancelText,
                style: AppFonts.button.copyWith(
									color: AppColors.textSecondary,
								),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: effectiveConfirmColor,
              ),
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: Text(
                confirmText,
                style: AppFonts.button.copyWith(
                  color: effectiveConfirmColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }
}