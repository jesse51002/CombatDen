import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/cancel_outcome.dart';
import 'package:crm/features/member_details/presentation/dialogs/cancel_membership/cancel_target.dart';

/// Completion body for the cancel dialog — shown after the
/// backend responds (success or failure).
///
/// Lists each succeeded membership under a "Cancelled" heading
/// (with a green check icon) and, when any failed, lists them
/// under a "Couldn't cancel" heading (with a red error icon).
///
/// [targets] is the full selection from the Review step;
/// [outcome] carries the succeeded/failed item_id split from
/// the repository. Both are needed to label rows by member name
/// + plan (the outcome only carries item_ids).
class CancelCompleteList extends StatelessWidget {
  final List<CancelTarget> targets;
  final CancelOutcome outcome;

  const CancelCompleteList({
    super.key,
    required this.targets,
    required this.outcome,
  });

  @override
  Widget build(BuildContext context) {
    final succeededSet = outcome.succeededItemIds.toSet();
    final failedSet = outcome.failedItemIds.toSet();

    final succeeded =
        targets.where((t) => succeededSet.contains(t.itemId)).toList();
    final failed =
        targets.where((t) => failedSet.contains(t.itemId)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        if (succeeded.isNotEmpty)
          _Section(
            icon: Symbols.check_circle_sharp,
            iconColor: DesignConstants.goodGreen,
            heading: 'Cancelled',
            targets: succeeded,
          ),
        if (failed.isNotEmpty)
          _Section(
            icon: Symbols.error_sharp,
            iconColor: DesignConstants.badRed,
            heading: "Couldn't cancel",
            note:
                'These memberships weren\'t cancelled — '
                'a Stripe error prevented it. '
                'Reload and try again.',
            targets: failed,
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String heading;
  final String? note;
  final List<CancelTarget> targets;

  const _Section({
    required this.icon,
    required this.iconColor,
    required this.heading,
    required this.targets,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(heading, style: DesignConstants.h3),
        if (note != null)
          Text(
            note!,
            style: DesignConstants.h3.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
        Column(
          spacing: DesignConstants.spacingSmall,
          children: targets
              .map(
                (t) => _CompletionRow(
                  icon: icon,
                  iconColor: iconColor,
                  target: t,
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _CompletionRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final CancelTarget target;

  const _CompletionRow({
    required this.icon,
    required this.iconColor,
    required this.target,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        Icon(
          icon,
          size: DesignConstants.iconSizeMedium,
          color: iconColor,
          weight: DesignConstants.iconWeight,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingTiny,
            children: [
              Text(
                target.planName,
                style: DesignConstants.p,
              ),
              Text(
                'for ${target.subjectName}',
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
              if (target.payerName != null)
                Text(
                  'paid by ${target.payerName}',
                  style: DesignConstants.pSmall.copyWith(
                    color: DesignConstants.text3rd,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
