import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// Primary action button — the landing page's signature gradient CTA: a
/// sapphire→accent-dark gradient with a soft layered shadow, white label, and
/// an optional leading icon. Mirrors `GWButton` primary in
/// `LandingPage/hifi/chrome.jsx`.
///
/// Pass [backgroundColor] to override the gradient with a solid fill (e.g. a
/// destructive red) — that also drops the blue CTA shadow. When [textColor] is
/// omitted the label/spinner colour auto-contrasts against the fill: near-white
/// on the gradient or a dark fill, near-black on a light fill (e.g. `okYellow`
/// gold in dark mode), via [DesignConstants.onFill]. All visuals come from
/// [DesignConstants].
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
    // No solid fill → the default gradient CTA (dark in both themes) → the
    // near-white accent label. A solid [backgroundColor] may be light in one
    // theme (e.g. okYellow gold in dark mode), so pick the contrasting ink by
    // its luminance instead of assuming near-white.
    final fg = textColor ??
        (backgroundColor == null
            ? DesignConstants.onAccent
            : DesignConstants.onFill(backgroundColor!));
    final style = (textStyle ?? DesignConstants.h3).copyWith(color: fg);
    final radius = borderRadius ?? DesignConstants.radiusBig;
    final pad = padding ??
        const EdgeInsets.symmetric(
          horizontal: DesignConstants.paddingSmall,
          vertical: DesignConstants.spacingMedium,
        );
    final enabled = onPressed != null && !isLoading;
    // Default look is the gradient CTA; a custom backgroundColor swaps in a
    // solid fill (and drops the blue CTA shadow).
    final solid = backgroundColor != null;

    final content = isLoading
        ? SizedBox(
            height: DesignConstants.iconSizeMedium,
            width: DesignConstants.iconSizeMedium,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(fg),
            ),
          )
        : icon != null
            ? Row(
                mainAxisSize:
                    fullWidth ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: DesignConstants.spacingSmall,
                children: [icon!, Text(text, style: style)],
              )
            : Text(text, style: style);

    final button = Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: solid ? backgroundColor : null,
          gradient: solid ? null : DesignConstants.primaryGradient,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: solid ? null : DesignConstants.buttonShadow,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: BorderRadius.circular(radius),
            child: Padding(
              padding: pad,
              // Only center when stretched full-width; otherwise shrink-wrap so
              // the button doesn't expand to its parent's height (e.g. a nav
              // bar). `Center` with bounded height would fill it.
              child: fullWidth ? Center(child: content) : content,
            ),
          ),
        ),
      ),
    );

    if (fullWidth) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}
