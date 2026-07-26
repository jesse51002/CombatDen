import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';

/// The plain confirmation that a membership was picked, at the TOP of the plan
/// step's body.
///
/// It names the plan and only the plan: the pinned identity strip above already
/// says WHO the choice is for. It never names a PRICE — money on this kiosk
/// comes from the server preview on the review screen, never derived from a
/// plan row.
class FlowPlanPickedBanner extends StatelessWidget {
  final String planName;

  /// WHICH of the person's picked memberships this is, and how many there are.
  ///
  /// A surface that sells one membership per person has nothing to count and
  /// leaves both at 1; a surface that sells several needs each banner to say
  /// which one it is, or the discounts hanging off two of them are ambiguous.
  /// The [MembershipFlowCopy] in force decides whether the count is spoken.
  final int index;
  final int total;

  const FlowPlanPickedBanner({
    super.key,
    required this.planName,
    this.index = 1,
    this.total = 1,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final copy = MembershipFlowTheme.copyOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.paddingBig,
        vertical: DesignConstants.spacingLarge,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.primaryColor10,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      ),
      child: Row(
        spacing: DesignConstants.spacingMedium,
        children: [
          const _Check(),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: DesignConstants.spacingTiny,
              children: [
                Text(
                  copy.pickedEyebrow(index: index, total: total),
                  style: scale.eyebrow.copyWith(
                    color: DesignConstants.primaryColor,
                  ),
                ),
                Text(
                  planName,
                  style: scale.statement,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The sapphire tick disc, matching the plan card's selected mark.
class _Check extends StatelessWidget {
  const _Check();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: DesignConstants.iconSizeBig,
      height: DesignConstants.iconSizeBig,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: DesignConstants.primaryColor,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Symbols.check_sharp,
        size: DesignConstants.iconSizeSmall,
        weight: DesignConstants.iconWeight,
        color: DesignConstants.onAccent,
      ),
    );
  }
}
