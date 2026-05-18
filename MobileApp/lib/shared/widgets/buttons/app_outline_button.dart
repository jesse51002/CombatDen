import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';

/// Outlined pill-style button. Defaults to a fully-rounded pill with
/// `text` border at `buttonBorder` weight.
class AppOutlineButton extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    final border = borderColor ?? DesignConstants.text;
    final width = borderWidth ?? DesignConstants.buttonBorder;
    final fg = textColor ?? DesignConstants.text;
    final style = (textStyle ?? DesignConstants.p).copyWith(color: fg);
    final radius = borderRadius ?? DesignConstants.radiusCircle;
    final pad =
        padding ??
        EdgeInsets.symmetric(
          horizontal: DesignConstants.paddingSmall,
          vertical: DesignConstants.spacingMedium,
        );

    final button = OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: fg,
        side: BorderSide(color: border, width: width),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
        padding: pad,
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
