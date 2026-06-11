import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_result_item.dart';

/// One per-membership result line in the breakdown:
/// created (✓) or failed (✗ + the error), labelled with
/// the member and plan.
class StartResultRow extends StatelessWidget {
  final MemberMembershipsStartResultItem item;
  final String memberName;
  final String planName;

  /// Set on created rows — the "link to the membership".
  final VoidCallback? onView;

  const StartResultRow({
    super.key,
    required this.item,
    required this.memberName,
    required this.planName,
    this.onView,
  });

  @override
  Widget build(BuildContext context) {
    final created = item.isCreated;
    final color = created
        ? DesignConstants.goodGreen
        : DesignConstants.badRed;
    final row = Container(
      padding: const EdgeInsets.all(
        DesignConstants.paddingSmall,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.backgroundColor,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
        border: Border.all(color: DesignConstants.divider),
      ),
      child: Row(
        spacing: DesignConstants.spacingMedium,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            created
                ? Symbols.check_circle_sharp
                : Symbols.cancel_sharp,
            weight: DesignConstants.iconWeight,
            size: DesignConstants.iconSizeLarge,
            color: color,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              spacing: DesignConstants.spacingTiny,
              children: [
                Text(
                  '$memberName · $planName',
                  style: DesignConstants.pSemibold,
                ),
                Text(
                  created
                      ? 'Created — tap to view the '
                          'membership'
                      : item.error ?? 'Failed',
                  style:
                      DesignConstants.pSmall.copyWith(
                    color: created
                        ? DesignConstants.text2nd
                        : DesignConstants.badRed,
                  ),
                ),
              ],
            ),
          ),
          Text(
            item.status.displayLabel,
            style: DesignConstants.pSmallSemibold
                .copyWith(color: color),
          ),
        ],
      ),
    );
    if (onView == null) return row;
    return InkWell(
      onTap: onView,
      borderRadius: BorderRadius.circular(
        DesignConstants.radiusSmall,
      ),
      child: row,
    );
  }
}
