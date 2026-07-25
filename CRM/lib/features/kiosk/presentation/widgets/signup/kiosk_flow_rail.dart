import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The SOLO signup's step labels — the 6-step template the rail renders while
/// the roster holds only the payer.
const List<String> kKioskSoloFlowSteps = [
  'You',
  'Details',
  'Plan',
  'Waiver',
  'Card',
  'Pay',
];

/// The GROUP template (ruling 8): the moment a second person joins the roster,
/// "People" becomes a step of its own and the rail re-labels to seven.
///
/// The rail always RENDERS — the people step is always visited, even solo
/// ("It's just me" → Plans) — so what changes is the labelling, never whether
/// the rail exists.
const List<String> kKioskGroupFlowSteps = [
  'You',
  'Details',
  'People',
  'Plans',
  'Waivers',
  'Card',
  'Pay',
];

/// "Where am I in the signup" — a horizontal numbered rail across the top of
/// every step.
///
/// Built from the shipped `KioskAppSteps` recipe (the sapphire numbered disc +
/// its label), laid on its side with hairline connectors. A completed step
/// swaps its numeral for a check; the current step's disc carries a soft halo
/// so it reads as "here" from standing distance.
///
/// [steps] is passed rather than derived so the same widget serves both the
/// solo and group templates — see [kKioskSoloFlowSteps] /
/// [kKioskGroupFlowSteps].
///
/// **It SCALES rather than clips on a narrow fold.** The rungs are intrinsically
/// sized, so the 7-rung group template is wider than the 6-rung solo one and can
/// out-measure a short fold's content rail — and a clipped rail loses exactly
/// the rungs a member has not reached yet, which is the half that tells them how
/// much is left. The `BoxFit.scaleDown` is a NO-OP whenever the rail fits (the
/// normal case) and otherwise shrinks the whole rail **as a set**, so the discs,
/// labels and connectors keep their proportions to each other instead of one
/// being singled out. This is the same "a short fold scales, never overflows"
/// rule the get-app modal's `ShrinkToFit` applies vertically.
class KioskFlowRail extends StatelessWidget {
  final List<String> steps;

  /// Zero-based index of the step the member is on. Everything before it is
  /// drawn as done.
  final int current;

  const KioskFlowRail({
    super.key,
    required this.steps,
    required this.current,
  });

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingMedium,
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0) _RailLink(done: i <= current),
            _RailStep(
              number: i + 1,
              label: steps[i],
              done: i < current,
              now: i == current,
            ),
          ],
        ],
      ),
    );
  }
}

/// One rung: the disc and its label.
class _RailStep extends StatelessWidget {
  final int number;
  final String label;
  final bool done;
  final bool now;

  const _RailStep({
    required this.number,
    required this.label,
    required this.done,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        _RailDisc(number: number, done: done, now: now),
        Text(
          label,
          style: DesignConstants.kioskCaption.copyWith(
            // A rail label is a muted WORD, so even the resting rung stays on
            // the kiosk's AA floor (`text2nd`) rather than dropping to
            // `text3rd`. Emphasis comes from ink + weight, not from contrast
            // a member can't read at 2m.
            color: now ? DesignConstants.text : DesignConstants.text2nd,
            fontWeight: now ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// The numbered disc — the `KioskAppSteps` `_StepNumber` recipe, one size up
/// (the rail is read at a glance across the whole stage, not inside a card)
/// and with the done / now states the rail needs.
class _RailDisc extends StatelessWidget {
  final int number;
  final bool done;
  final bool now;

  const _RailDisc({
    required this.number,
    required this.done,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    final filled = done || now;
    return Container(
      width: DesignConstants.iconSizeBig,
      height: DesignConstants.iconSizeBig,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? DesignConstants.primaryColor : DesignConstants.line,
        shape: BoxShape.circle,
        boxShadow: now ? DesignConstants.buttonShadow : null,
      ),
      child: done
          ? Icon(
              Symbols.check_sharp,
              size: DesignConstants.iconSizeTiny,
              weight: DesignConstants.iconWeight,
              color: DesignConstants.onAccent,
            )
          : Text(
              '$number',
              style: DesignConstants.kioskCaption.copyWith(
                fontWeight: FontWeight.w700,
                color:
                    filled ? DesignConstants.onAccent : DesignConstants.text2nd,
              ),
            ),
    );
  }
}

/// The hairline connector between two rungs. It carries no words, so it stays
/// on the non-text tokens.
class _RailLink extends StatelessWidget {
  final bool done;

  const _RailLink({required this.done});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: DesignConstants.spacingBig,
      height: DesignConstants.progressBarThickness,
      decoration: BoxDecoration(
        color: done
            ? DesignConstants.primaryColor.withValues(alpha: 0.45)
            : DesignConstants.line,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      ),
    );
  }
}
