import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_controller.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';

/// Scaffold for the post-class celebration cards (Streak, Wins, Points,
/// Rewards, Rank). Provides a fixed body area, an optional close (X) button
/// in the upper-right, and a full-width primary CTA pinned to the bottom.
///
/// When a [controller] is supplied, the CTA is hidden (and tap targets are
/// disabled) while the controller reports `isAnimating == true`. Tapping
/// anywhere on the body area during that window calls
/// [PostClassController.requestSkip], which the body widget should turn
/// into a jump-to-final-state. Once the body calls
/// [PostClassController.markDone] the CTA fades back in.
class PostClassScaffold extends StatelessWidget {
  const PostClassScaffold({
    super.key,
    required this.body,
    required this.ctaLabel,
    required this.onCtaPressed,
    this.header,
    this.onClose,
    this.controller,
  });

  final Widget body;
  final String ctaLabel;
  final VoidCallback onCtaPressed;
  final Widget? header;
  final VoidCallback? onClose;
  final PostClassController? controller;

  static const Duration _kCtaFade = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    return AppScreenScaffold(
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              vertical: DesignConstants.spacingBig,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: DesignConstants.spacingBig,
              children: [
                ?header,
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => controller?.requestSkip(),
                    child: Center(child: body),
                  ),
                ),
                _AnimatedCta(
                  controller: controller,
                  fadeDuration: _kCtaFade,
                  child: AppPrimaryButton(
                    text: ctaLabel,
                    onPressed: onCtaPressed,
                    fullWidth: true,
                    borderRadius: DesignConstants.radiusBig,
                    textStyle: DesignConstants.h2,
                  ),
                ),
              ],
            ),
          ),
          if (onClose case final close?)
            Positioned(
              top: DesignConstants.spacingLarge,
              right: DesignConstants.spacingLarge,
              child: IconButton(
                onPressed: close,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(
                  Symbols.close_sharp,
                  color: DesignConstants.text,
                  weight: DesignConstants.iconWeight,
                  size: DesignConstants.iconSizeXl,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Wraps the CTA in a fade + IgnorePointer that follows the controller's
/// `isAnimating`. With no controller the CTA is always visible.
class _AnimatedCta extends StatelessWidget {
  const _AnimatedCta({
    required this.controller,
    required this.fadeDuration,
    required this.child,
  });

  final PostClassController? controller;
  final Duration fadeDuration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ctrl = controller;
    if (ctrl == null) {
      return child;
    }
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final hidden = ctrl.isAnimating;
        return IgnorePointer(
          ignoring: hidden,
          child: AnimatedOpacity(
            opacity: hidden ? 0 : 1,
            duration: fadeDuration,
            curve: Curves.easeOutQuart,
            child: child,
          ),
        );
      },
    );
  }
}
