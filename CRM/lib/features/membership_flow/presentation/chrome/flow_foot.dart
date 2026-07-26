import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_buttons.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// Every signup step's system footer: a hairline band over THREE columns — the
/// escape exiled to the far LEFT, the Back / primary pair centred, and an
/// optional Skip in the mirror gutter on the right.
///
/// It keeps the kiosk's one rule: the way out is along the bottom hairline,
/// bottom-left. Skip cannot join the middle pair — the two gutters are
/// different verbs at different scales (leave the FLOW / skip this STEP) and
/// stay a full stage apart so neither can be mis-tapped for the other.
///
/// Skip is never a discard: it carries whatever was typed forward exactly as
/// Continue does, for the member who typed nothing.
class FlowFoot extends StatelessWidget {
  /// The middle column's primary. Null disables it (an incomplete form).
  final VoidCallback? onPrimary;
  final String primaryLabel;

  /// The middle column's Back. Omitted on step 1 — home is where they came
  /// from, and the escape already answers that.
  final VoidCallback? onBack;

  /// The right gutter's Skip. Omitted where the step has nothing to skip.
  final VoidCallback? onSkip;
  final String skipLabel;

  /// Ask "Start over?" before abandoning, instead of leaving on first tap.
  /// Proportional to what is lost: only the card and review steps pass `true`,
  /// since a confirm on an early step is a second trap for a member who
  /// already mis-tapped.
  final bool confirmAbandon;

  const FlowFoot({
    super.key,
    required this.onPrimary,
    this.primaryLabel = 'Continue',
    this.onBack,
    this.onSkip,
    this.skipLabel = 'Skip for now',
    this.confirmAbandon = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        const Hairline(),
        // A Stack, not a three-way Row: the decision pair is centred on the
        // WHOLE band, so its optical centre is identical on every step whatever
        // the gutters carry, and the longest primary the foot ever carries can
        // never squeeze a gutter into an overflow on a short fold.
        Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerLeft,
                child: _EscapeGutter(confirm: confirmAbandon),
              ),
            ),
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerRight,
                child: _SkipGutter(onSkip: onSkip, label: skipLabel),
              ),
            ),
            _Decisions(
              onPrimary: onPrimary,
              primaryLabel: primaryLabel,
              onBack: onBack,
            ),
          ],
        ),
      ],
    );
  }
}

/// The far-left escape. Ghost tier, the ONLY tier used for leaving a flow.
/// The wording answers the SCREEN, not the navigation: beside a
/// `Sign Membership · $149.00` button "Cancel" would read as *cancel the
/// payment*, so the signup escape is always "Start over".
class _EscapeGutter extends StatelessWidget {
  final bool confirm;

  const _EscapeGutter({required this.confirm});

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    // Pulled left by the button's own horizontal padding so the GLYPH lands on
    // the step's content rail; the tap target keeps its full padded width.
    return Transform.translate(
      offset: Offset(-scale.buttonGhostPadding.left, 0),
      child: FlowGhostButton(
        text: 'Start over',
        onPressed: () {
          final cubit = context.read<KioskSignupCubit>();
          if (confirm) {
            cubit.askAbandon();
          } else {
            cubit.abandon();
          }
        },
      ),
    );
  }
}

/// The centred decision pair — the same slot on every step.
class _Decisions extends StatelessWidget {
  final VoidCallback? onPrimary;
  final String primaryLabel;
  final VoidCallback? onBack;

  const _Decisions({
    required this.onPrimary,
    required this.primaryLabel,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final back = onBack;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingLarge,
      children: [
        if (back != null) FlowOutlineButton(text: 'Back', onPressed: back),
        FlowPrimaryButton(text: primaryLabel, onPressed: onPrimary),
      ],
    );
  }
}

/// The mirror gutter. Quieter than the primary by a tier but never the ghost
/// escape tier, which the flow reserves for leaving — so it rides
/// `FlowOutlineButton`, the wrapper that is the ONE place the surface's
/// button metrics are applied.
class _SkipGutter extends StatelessWidget {
  final VoidCallback? onSkip;
  final String label;

  const _SkipGutter({required this.onSkip, required this.label});

  @override
  Widget build(BuildContext context) {
    final skip = onSkip;
    if (skip == null) return const SizedBox.shrink();
    return FlowOutlineButton(text: label, onPressed: skip);
  }
}
