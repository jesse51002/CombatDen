import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';
import 'package:mobile_app/shared/widgets/post_class/celebration_data.dart';

/// The single primary action, wrapped in the fade + `IgnorePointer` that
/// follows the controller's `isAnimating`.
///
/// This is the whole "CTA hidden during the intro, faded in on
/// `markDone`" contract. It lives in one part so all five layouts get it
/// by construction rather than by each remembering to reimplement it.
/// With no controller the CTA is always visible (the Wins card ships
/// that way).
class CelebrationCta extends StatelessWidget {
  const CelebrationCta({super.key, required this.data});

  final CelebrationData data;

  static const Duration _kFade = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    final button = AppPrimaryButton(
      text: data.ctaLabel,
      onPressed: data.onCtaPressed,
      fullWidth: true,
      borderRadius: DesignConstants.radiusBig,
      textStyle: DesignConstants.h2,
    );

    final ctrl = data.controller;
    if (ctrl == null) {
      return button;
    }
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final hidden = ctrl.isAnimating;
        return IgnorePointer(
          ignoring: hidden,
          child: AnimatedOpacity(
            opacity: hidden ? 0 : 1,
            duration: _kFade,
            curve: Curves.easeOutQuart,
            child: button,
          ),
        );
      },
    );
  }
}
