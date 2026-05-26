import 'package:flutter/material.dart';
import 'package:customization_engine/showcase/showcase_tokens.dart';

/// Clone of MobileApp's `AppPrimaryButton`: primary action button on the
/// brand fill. Preview-only — [onPressed] defaults to a no-op.
class ShowcasePrimaryButton extends StatelessWidget {
  const ShowcasePrimaryButton({
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
    final bg = backgroundColor ?? ShowcaseTokens.primaryColor;
    final fg = textColor ?? ShowcaseTokens.primaryButtonText;
    final style = (textStyle ?? ShowcaseTokens.h3).copyWith(color: fg);
    final radius = borderRadius ?? ShowcaseTokens.radiusSmall;
    final pad =
        padding ??
        const EdgeInsets.symmetric(
          horizontal: ShowcaseTokens.paddingSmall,
          vertical: ShowcaseTokens.spacingMedium,
        );

    final button = ElevatedButton(
      onPressed: onPressed ?? () {},
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
              spacing: ShowcaseTokens.spacingSmall,
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
