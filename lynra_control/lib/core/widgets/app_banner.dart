import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_fonts.dart';

class AppBanner {
  AppBanner._();

  static void show({
    required BuildContext context,
    required String message,
    IconData icon = Icons.info_outline,
    Color? color,
    Duration duration = const Duration(seconds: 3),
  }) {
    final messenger = ScaffoldMessenger.of(context);
		final bannerColor = color ?? AppColors.primary;
    messenger.hideCurrentMaterialBanner();

    messenger.showMaterialBanner(
      MaterialBanner(
        backgroundColor: bannerColor.withValues(alpha: 0.10),
        elevation: 0,
        leading: Icon(
          icon,
          color: bannerColor,
        ),
        content: Text(
          message,
          style: AppFonts.body.copyWith(
						color: bannerColor,
					),
        ),
        actions: [
          TextButton(
            onPressed: messenger.hideCurrentMaterialBanner,
            child: Text(
							'OK',
							style: AppFonts.button.copyWith(
								color: bannerColor,
							),
						),
          ),
        ],
      ),
    );

    Future.delayed(duration, () {
      messenger.hideCurrentMaterialBanner();
    });
  }

  static void success(
    BuildContext context,
    String message,
  ) {
    show(
      context: context,
      message: message,
      icon: Icons.check_circle_outline,
      color: AppColors.success,
    );
  }

  static void warning(
    BuildContext context,
    String message,
  ) {
    show(
      context: context,
      message: message,
      icon: Icons.warning_amber_rounded,
      color: AppColors.warning,
    );
  }

  static void error(
    BuildContext context,
    String message,
  ) {
    show(
      context: context,
      message: message,
      icon: Icons.error_outline,
      color: AppColors.danger,
    );
  }

  static void info(
    BuildContext context,
    String message,
  ) {
    show(
      context: context,
      message: message,
      icon: Icons.info_outline,
      color: AppColors.textPrimary,
    );
  }
}