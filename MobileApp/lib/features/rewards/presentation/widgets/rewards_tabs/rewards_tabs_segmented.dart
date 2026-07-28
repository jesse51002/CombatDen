import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/rewards_tabs/rewards_tabs.dart';

/// `RewardsTabsLayout.segmented` — both tabs inside one pill, the active
/// one filled. Same two labelled tap targets as the underline strip;
/// only the chrome differs.
class RewardsTabsSegmented extends StatelessWidget {
  const RewardsTabsSegmented({
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
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: DesignConstants.screenHorizontalPadding,
      ),
      child: Container(
        padding: EdgeInsets.all(DesignConstants.spacingSmall),
        decoration: BoxDecoration(
          color: DesignConstants.card,
          borderRadius: BorderRadius.circular(DesignConstants.radiusCircle),
        ),
        child: Row(
          spacing: DesignConstants.spacingSmall,
          children: [
            Expanded(
              child: _Segment(
                label: 'Points Store',
                isActive: active == RewardsTab.pointsStore,
                onTap: onPointsStoreTap,
              ),
            ),
            Expanded(
              child: _Segment(
                label: 'My Rewards',
                isActive: active == RewardsTab.myRewards,
                onTap: onMyRewardsTap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.isActive,
    this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: DesignConstants.spacingMedium,
        ),
        decoration: BoxDecoration(
          color: isActive
              ? DesignConstants.accent
              : DesignConstants.backgroundColor.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(DesignConstants.radiusCircle),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DesignConstants.h2.copyWith(
            color: isActive
                ? DesignConstants.primaryButtonText
                : DesignConstants.text2nd,
          ),
        ),
      ),
    );
  }
}
