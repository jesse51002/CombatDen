import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// Every signup step's system footer: a hairline band over THREE columns —
/// the escape exiled to the far LEFT, the Back / primary pair centred, and an
/// optional Skip in the mirror gutter on the right.
///
/// The hairline + gutter come from `KioskEscapeFoot` and the band itself from
/// `KioskGlanceFoot`, so the kiosk keeps its one rule: **the way out is along
/// the bottom hairline, bottom-left.** The middle pair holds the flow's
/// rhythm and must keep its exact optical centre on every step, which is why
/// Skip cannot join it — the two gutters are different verbs at different
/// scales (leave the FLOW / skip this STEP) and are a full stage apart, so
/// neither can be mis-tapped for the other or for the primary.
///
/// **Skip is never a discard.** It carries whatever was typed forward exactly
/// as Continue does; it exists to tell the member who typed nothing that they
/// may move on. A destructive control one gutter from the primary is precisely
/// the mis-tap the whole abandon contract avoids.
///
/// [confirmAbandon] decides whether the escape asks first. Confirmation is
/// proportional to what is lost: the early steps abandon on the first tap (at
/// most ~20 seconds of retyping, and a confirm is a second trap for a member
/// who already mis-tapped), while the card and review steps — where real work
/// dies — pass `true`.
class KioskFlowFoot extends StatelessWidget {
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
  final bool confirmAbandon;

  const KioskFlowFoot({
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
        Row(
          children: [
            Expanded(child: _EscapeGutter(confirm: confirmAbandon)),
            _Decisions(
              onPrimary: onPrimary,
              primaryLabel: primaryLabel,
              onBack: onBack,
            ),
            Expanded(
              child: _SkipGutter(onSkip: onSkip, label: skipLabel),
            ),
          ],
        ),
      ],
    );
  }
}

/// The far-left escape. Ghost tier, and the ONLY tier used for leaving a flow.
///
/// The wording answers the SCREEN, not the navigation: beside a `Pay $149.00`
/// button "Cancel" would read as *cancel the payment*, so the kiosk's signup
/// escape is always "Start over".
class _EscapeGutter extends StatelessWidget {
  final bool confirm;

  const _EscapeGutter({required this.confirm});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      // Pulled left by exactly the button's own horizontal padding so the
      // GLYPH lands on the step's content rail rather than a pad-width inside
      // it — the same optical correction `KioskEscapeFoot` makes. The tap
      // target keeps its full padded width.
      child: Transform.translate(
        offset: Offset(-DesignConstants.kioskButtonGhostPadding.left, 0),
        child: KioskGhostButton(
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
      ),
    );
  }
}

/// The centred decision pair — the flow's rhythm, in the same slot on every
/// step.
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
        if (back != null) KioskOutlineButton(text: 'Back', onPressed: back),
        KioskPrimaryButton(text: primaryLabel, onPressed: onPrimary),
      ],
    );
  }
}

/// The mirror gutter. Quieter than the gradient primary by a full tier (per
/// "skipping is the quieter option") but never the ghost escape tier, which
/// the kiosk reserves for leaving a flow and nothing else — so it rides
/// `KioskOutlineButton`, exactly like Back.
///
/// It goes through the kiosk button wrapper rather than styling an
/// `AppOutlineButton` at the call site: those wrappers are the ONE place the
/// kiosk button tokens are applied, so the whole set scales together and no
/// call site ever restates a size.
class _SkipGutter extends StatelessWidget {
  final VoidCallback? onSkip;
  final String label;

  const _SkipGutter({required this.onSkip, required this.label});

  @override
  Widget build(BuildContext context) {
    final skip = onSkip;
    if (skip == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerRight,
      child: KioskOutlineButton(text: label, onPressed: skip),
    );
  }
}
