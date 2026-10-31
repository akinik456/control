import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_fonts.dart';

class AppInfoDialog {
  AppInfoDialog._();

  static Future<void> show({
    required BuildContext context,
    required String title,
    required String message,
    required String confirmText,
    required String cancelText,
    required Future<void> Function() onConfirm,
    bool barrierDismissible = true,
    Color? confirmColor,
  }) {
		final effectiveConfirmColor =
    confirmColor ?? AppColors.primary;
    return showDialog<void>(
      context: context,
      barrierDismissible: barrierDismissible,
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
                Navigator.pop(dialogContext);
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
              onPressed: () async {
                Navigator.pop(dialogContext);
                await onConfirm();
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
  }
}