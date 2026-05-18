import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';

/// Primary action button with orange background.
class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.fullWidth = false,
    this.backgroundColor,
    this.textColor,
    this.textStyle,
    this.padding,
    this.borderRadius,
    this.icon,
  });

  final String text;
  final VoidCallback? onPressed;
  final bool fullWidth;
  final Color? backgroundColor;
  final Color? textColor;
  final TextStyle? textStyle;
  final EdgeInsetsGeometry? padding;
  final double? borderRadius;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? DesignConstants.primaryColor;
    final fg = textColor ?? DesignConstants.text;
    final style = (textStyle ?? DesignConstants.h3).copyWith(color: fg);
    final radius = borderRadius ?? DesignConstants.radiusSmall;
    final pad =
        padding ??
        EdgeInsets.symmetric(
          horizontal: DesignConstants.paddingSmall,
          vertical: DesignConstants.spacingMedium,
        );

    final button = ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        disabledBackgroundColor: bg.withValues(alpha: 0.5),
        padding: pad,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
        elevation: 0,
      ),
      child: icon != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              spacing: DesignConstants.spacingSmall,
              children: [icon!, Text(text, style: style)],
            )
          : Text(text, style: style),
    );

    if (fullWidth) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}
