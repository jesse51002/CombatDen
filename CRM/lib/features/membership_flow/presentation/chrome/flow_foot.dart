import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_buttons.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// Every purchase step's system footer: a hairline band over THREE columns —
/// the escape exiled to the far LEFT, the Back / primary pair centred, and an
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

  /// The primary's words. Null takes the surface's own forward action.
  final String? primaryLabel;

  /// The middle column's Back. Omitted on step 1 — home is where they came
  /// from, and the escape already answers that.
  final VoidCallback? onBack;

  /// The right gutter's Skip. Omitted where the step has nothing to skip.
  final VoidCallback? onSkip;
  final String? skipLabel;

  /// Leave the flow. Non-null on every step the member or staff may still
  /// leave: a step that could omit its way out is a step that eventually does.
  ///
  /// Null is the ONE deliberate exception, and it is not "this step has no
  /// escape yet" — it is a TERMINAL step, after PAY, where leaving would
  /// strand a charge whose outcome nobody has read. The kiosk reached the same
  /// conclusion from the other side and routed its receipt around this widget
  /// entirely (`kiosk_results_foot.dart`); the absence is expressed here
  /// instead so both surfaces state it in one place. Rendering the ghost
  /// button anyway and wiring it to nothing is the failure this replaces — a
  /// visible way out that does not work is worse than none.
  final VoidCallback? onEscape;

  /// The escape's wording, which answers the SCREEN rather than the
  /// navigation: beside a `Sign Membership · $149.00` button "Cancel" would
  /// read as *cancel the payment*. Null takes the surface's own escape word.
  final String? escapeLabel;

  const FlowFoot({
    super.key,
    required this.onPrimary,
    required this.onEscape,
    this.primaryLabel,
    this.onBack,
    this.onSkip,
    this.skipLabel,
    this.escapeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final copy = MembershipFlowTheme.copyOf(context);
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
            if (onEscape case final escape?)
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _EscapeGutter(
                    label: escapeLabel ?? copy.escapeAction,
                    onEscape: escape,
                  ),
                ),
              ),
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerRight,
                child: _SkipGutter(
                  onSkip: onSkip,
                  label: skipLabel ?? copy.skipAction,
                ),
              ),
            ),
            _Decisions(
              onPrimary: onPrimary,
              primaryLabel: primaryLabel ?? copy.continueAction,
              onBack: onBack,
            ),
          ],
        ),
      ],
    );
  }
}

/// The far-left escape. Ghost tier, the ONLY tier used for leaving a flow.
class _EscapeGutter extends StatelessWidget {
  final String label;
  final VoidCallback onEscape;

  const _EscapeGutter({required this.label, required this.onEscape});

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    // Pulled left by the button's own horizontal padding so the GLYPH lands on
    // the step's content rail; the tap target keeps its full padded width.
    return Transform.translate(
      offset: Offset(-scale.buttonGhostPadding.left, 0),
      child: FlowGhostButton(text: label, onPressed: onEscape),
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
    final copy = MembershipFlowTheme.copyOf(context);
    final back = onBack;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingLarge,
      children: [
        if (back != null)
          FlowOutlineButton(text: copy.backAction, onPressed: back),
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
