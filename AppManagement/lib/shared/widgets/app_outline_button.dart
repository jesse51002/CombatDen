import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';

/// Outlined button with customizable border and text.
///
/// Fully rounded by default with border weight 2 and
/// [DesignConstants.text] border color. All visual
/// properties are customizable.
class AppOutlineButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool fullWidth;
  final Color? borderColor;
  final double? borderWidth;
  final Color? textColor;
  final TextStyle? textStyle;
  final EdgeInsetsGeometry? padding;
  final double? borderRadius;
  final Widget? icon;

  const AppOutlineButton({
    super.key,
    required this.text,
    this.onPressed,
    this.fullWidth = false,
    this.borderColor,
    this.borderWidth,
    this.textColor,
    this.textStyle,
    this.padding,
    this.borderRadius,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final border =
        borderColor ?? DesignConstants.text;
    final width = borderWidth ?? 2.0;
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

    final button = OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: fg,
        side: BorderSide(
          color: border,
          width: width,
        ),
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.circular(radius),
        ),
        padding: pad,
      ),
      child: icon != null
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
