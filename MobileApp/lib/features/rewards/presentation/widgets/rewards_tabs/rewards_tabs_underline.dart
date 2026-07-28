import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/rewards_tabs/rewards_tabs.dart';

/// `RewardsTabsLayout.underline` — the strip that ships today. Mimics
/// the underline-on-active treatment from the design; the inactive tab
/// is dim and has no underline.
class RewardsTabsUnderline extends StatelessWidget {
  const RewardsTabsUnderline({
    super.key,
    required this.active,
    this.onPointsStoreTap,
    this.onMyRewardsTap,
  });

  final RewardsTab active;
  final VoidCallback? onPointsStoreTap;
  final VoidCallback? onMyRewardsTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: DesignConstants.text3rd,
            width: DesignConstants.dividerThickness,
          ),
        ),
      ),
      padding: EdgeInsets.only(
        top: DesignConstants.spacingSmall,
        bottom: DesignConstants.spacingTiny,
        left: DesignConstants.paddingBig,
        right: DesignConstants.paddingBig,
      ),
      child: Row(
        spacing: DesignConstants.spacingBig,
        children: [
          Expanded(
            child: _TabItem(
              label: 'Points Store',
              isActive: active == RewardsTab.pointsStore,
              onTap: onPointsStoreTap,
            ),
          ),
          Expanded(
            child: _TabItem(
              label: 'My Rewards',
              isActive: active == RewardsTab.myRewards,
              onTap: onMyRewardsTap,
            ),
          ),
        ],
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.label,
    required this.isActive,
    this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = isActive
        ? DesignConstants.accent
        : DesignConstants.text2nd;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.only(bottom: DesignConstants.spacingMedium),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive
                  ? DesignConstants.accent
                  : DesignConstants.backgroundColor,
              width: DesignConstants.buttonBorder,
            ),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: DesignConstants.h2.copyWith(color: color),
        ),
      ),
    );
  }
}
