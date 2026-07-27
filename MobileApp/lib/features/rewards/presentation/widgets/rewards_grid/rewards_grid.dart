import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/rewards/data/models/redemption_record.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/reward_card.dart';

/// Two-column grid of the member's redemptions. Same shared card as the store,
/// but the CTA slot shows the redemption's status (Pending / Approved /
/// Rejected) and is non-interactive — a redemption is a historical record, not
/// a re-redeemable action.
class RewardsGrid extends StatelessWidget {
  const RewardsGrid({super.key, required this.redemptions});

  final List<RedemptionRecord> redemptions;

  @override
  Widget build(BuildContext context) {
    final left = <RedemptionRecord>[];
    final right = <RedemptionRecord>[];
    for (var i = 0; i < redemptions.length; i++) {
      (i.isEven ? left : right).add(redemptions[i]);
    }
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: DesignConstants.screenHorizontalPadding,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingLarge,
        children: [
          Expanded(child: _RewardsColumn(redemptions: left)),
          Expanded(child: _RewardsColumn(redemptions: right)),
        ],
      ),
    );
  }
}

class _RewardsColumn extends StatelessWidget {
  const _RewardsColumn({required this.redemptions});

  final List<RedemptionRecord> redemptions;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        for (final redemption in redemptions)
          RewardCard(
            imageUrl: redemption.imageUrl,
            title: redemption.title,
            priceLabel: redemption.priceLabel,
            pointsCost: redemption.pointCost,
            buttonText: _statusLabel(redemption.status),
            onPressed: null,
          ),
      ],
    );
  }
}

String _statusLabel(RedemptionStatus status) => switch (status) {
      RedemptionStatus.pending => 'Pending',
      RedemptionStatus.approved => 'Approved',
      RedemptionStatus.rejected => 'Rejected',
      RedemptionStatus.unknown => 'Redeemed',
    };
