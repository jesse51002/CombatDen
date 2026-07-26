import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';

/// "Where am I in the signup" — a horizontal numbered rail across the top of
/// every step, built from the `KioskAppSteps` disc laid on its side with
/// hairline connectors. A completed step swaps its numeral for a check; the
/// current step's disc carries a soft halo.
///
/// [steps] is passed rather than derived so one widget serves every spine: the
/// kiosk's 6-rung solo / 7-rung group templates and the desk's own, each owned
/// by the surface that walks them.
///
/// It SCALES rather than clips on a narrow fold: the 7-rung group template can
/// out-measure a short fold, and clipping would lose exactly the rungs the
/// member has not reached yet. `BoxFit.scaleDown` is a no-op whenever the rail
/// fits and otherwise shrinks discs, labels and connectors as a SET.
class FlowRail extends StatelessWidget {
  final List<String> steps;

  /// Zero-based index of the step the member is on. Everything before it is
  /// drawn as done.
  final int current;

  const FlowRail({
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
              total: steps.length,
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
///
/// The pair is ONE semantic node. A reader walking discs and words separately
/// hears "2" and then "Plans" with nothing tying them together and no way to
/// tell a passed rung from an unreached one, so the whole rung is announced as
/// a single sentence the surface's own copy composes.
class _RailStep extends StatelessWidget {
  final int number;
  final String label;
  final int total;
  final bool done;
  final bool now;

  const _RailStep({
    required this.number,
    required this.label,
    required this.total,
    required this.done,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final copy = MembershipFlowTheme.copyOf(context);
    return Semantics(
      label: copy.railStepSemantic(
        index: number - 1,
        total: total,
        label: label,
        done: done,
        current: now,
      ),
      selected: now,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingMedium,
        children: [
          _RailDisc(number: number, done: done, now: now),
          Text(
            label,
            style: scale.caption.copyWith(
              // A rail label is a muted WORD, so even a resting rung stays on
              // the kiosk's AA floor; emphasis comes from ink + weight, never
              // from contrast a member can't read at 2m.
              color: now ? DesignConstants.text : DesignConstants.text2nd,
              fontWeight: now ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// The numbered disc — the `KioskAppSteps` `_StepNumber` recipe one size up
/// (the rail is read across the whole stage, not inside a card), with the
/// done / now states.
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
    final scale = MembershipFlowTheme.of(context);
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
              style: scale.caption.copyWith(
                fontWeight: FontWeight.w700,
                color:
                    filled ? DesignConstants.onAccent : DesignConstants.text2nd,
              ),
            ),
    );
  }
}

/// The hairline connector between two rungs.
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
