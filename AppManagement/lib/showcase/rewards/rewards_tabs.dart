import 'package:flutter/material.dart';

import 'package:app_management/showcase/showcase_tokens.dart';

/// Which tab is currently selected in the rewards tab strip.
enum RewardsTab { pointsStore, myRewards }

/// Showcase clone of MobileApp's two-tab segmented selector. Mimics the
/// underline-on-active treatment from the design — the inactive tab is dim
/// and has no underline.
class RewardsTabs extends StatelessWidget {
  const RewardsTabs({
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
            color: ShowcaseTokens.text3rd,
            width: ShowcaseTokens.dividerThickness,
          ),
        ),
      ),
      padding: const EdgeInsets.only(
        top: ShowcaseTokens.spacingSmall,
        bottom: ShowcaseTokens.spacingTiny,
        left: ShowcaseTokens.paddingBig,
        right: ShowcaseTokens.paddingBig,
      ),
      child: Row(
        spacing: ShowcaseTokens.spacingBig,
        children: [
          Expanded(
            child: _RewardsTabItem(
              label: 'Points Store',
              isActive: active == RewardsTab.pointsStore,
              onTap: onPointsStoreTap,
            ),
          ),
          Expanded(
            child: _RewardsTabItem(
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

class _RewardsTabItem extends StatelessWidget {
  const _RewardsTabItem({
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
        ? ShowcaseTokens.accent
        : ShowcaseTokens.text2nd;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.only(bottom: ShowcaseTokens.spacingMedium),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive
                  ? ShowcaseTokens.accent
                  : ShowcaseTokens.backgroundColor,
              width: ShowcaseTokens.buttonBorder,
            ),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: ShowcaseTokens.h2.copyWith(color: color),
        ),
      ),
    );
  }
}
