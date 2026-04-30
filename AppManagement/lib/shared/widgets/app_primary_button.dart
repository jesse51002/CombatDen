import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';

/// Primary action button with orange background.
///
/// Fully rounded by default with [DesignConstants]
/// styling. All visual properties are customizable.
class AppPrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool fullWidth;
  final Color? backgroundColor;
  final Color? textColor;
  final TextStyle? textStyle;
  final EdgeInsetsGeometry? padding;
  final double? borderRadius;
  final Widget? icon;

  const AppPrimaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.fullWidth = false,
    this.backgroundColor,
    this.textColor,
    this.textStyle,
    this.padding,
    this.borderRadius,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final bg =
        backgroundColor ?? DesignConstants.primaryColor;
    final fg = textColor ?? DesignConstants.text;
    final style = (textStyle ?? DesignConstants.h3)
        .copyWith(color: fg);
    final radius =
        borderRadius ?? DesignConstants.radiusBig;
    final pad = padding ??
        const EdgeInsets.symmetric(
          horizontal: DesignConstants.paddingSmall,
          vertical: DesignConstants.spacingMedium,
        );

    final button = ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        disabledBackgroundColor:
            bg.withValues(alpha: 0.5),
        padding: pad,
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.circular(radius),
        ),
        elevation: 0,
      ),
      child: isLoading
          ? SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor:
                    AlwaysStoppedAnimation<Color>(fg),
              ),
            )
          : icon != null
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    icon!,
                    const SizedBox(
                      width:
                          DesignConstants.spacingSmall,
                    ),
                    Text(text, style: style),
                  ],
                )
              : Text(text, style: style),
    );

    if (fullWidth) {
      return SizedBox(
        width: double.infinity,
        child: button,
      );
    }

    return button;
  }
}
