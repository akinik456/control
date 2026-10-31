import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_fonts.dart';

class AppButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool outlined;
	final IconData? icon;
	
  const AppButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.outlined = false,
		this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = AppFonts.button.copyWith(
      fontSize: 16,
      color: outlined
          ? AppColors.primary
          : AppColors.background,
    );
		final buttonChild = icon == null
			? Text(text, style: textStyle)
			: Row(
					mainAxisSize: MainAxisSize.min,
					children: [
						Icon(icon, size: 20),
						const SizedBox(width: 8),
						Text(text, style: textStyle),
					],
				);
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: outlined
          ? OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: buttonChild,
            )
          : ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.background,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: buttonChild,
            ),
    );
  }
}