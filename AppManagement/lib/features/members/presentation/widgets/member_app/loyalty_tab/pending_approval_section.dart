import 'package:flutter/material.dart';

import 'package:app_management/core/state/selected_gym.dart';
import 'package:app_management/features/members/data/mock_loyalty.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/loyalty_tab/redemption_card.dart';
import 'package:app_management/shared/widgets/subtitle_section.dart';

// The demo member behind the single pending approval. The reward itself is
// live (the selected gym's store); only who/when/code is mock, since real
// per-member redemptions need a user backend that doesn't exist yet.
const String _kMemberName = 'Amy Traver';
const String _kCode = 'TXR-3K9P';
const String _kRequestedAt = 'Today, 6:12 PM';

// One redemption card is a single grid tile — cap it so it doesn't stretch
// the full pane (matches the store cards' tile scale).
const double _kCardMaxWidth = 260;

/// The loyalty tab's "Pending Redemption Approval" — a single approval built
/// from one of the selected gym's live store rewards, so its art / title /
/// points match the store. Hidden until the gym's rewards load.
class PendingApprovalSection extends StatelessWidget {
  const PendingApprovalSection({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: selectedGym,
      builder: (context, _) {
        final rewards = selectedGym.detail?.rewards;
        if (rewards == null || rewards.isEmpty) {
          return const SizedBox.shrink();
        }
        final reward = rewards.first;
        final pending = PendingRedemption(
          memberName: _kMemberName,
          rewardTitle: reward.title,
          priceLabel: reward.priceLabel,
          pointsCost: reward.pointsCost,
          imageUrl: reward.imageUrl,
          code: _kCode,
          requestedAt: _kRequestedAt,
        );
        return SubtitleSection(
          title: 'Pending Redemption Approval',
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _kCardMaxWidth),
              child: RedemptionCard(redemption: pending),
            ),
          ),
        );
      },
    );
  }
}
