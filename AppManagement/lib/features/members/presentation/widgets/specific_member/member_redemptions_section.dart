import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/core/state/selected_gym.dart';
import 'package:app_management/features/members/data/gym_detail.dart';
import 'package:app_management/features/members/data/mock_loyalty.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/loyalty_tab/redemptions_section.dart';
import 'package:app_management/shared/widgets/subtitle_section.dart';

/// The member-detail page's "Reward Redemptions" — the member's history pulled
/// live from the **selected gym's** store rewards (held in [selectedGym]
/// memory), so the art / titles / points match the style the gym is on. Each
/// mock redemption event (who / code / when / approved) is paired with one of
/// the gym's rewards. Mirrors the loyalty tab's `PendingApprovalSection`, which
/// builds its pending card from the same live source. Shows a message until the
/// gym's rewards load so the titled section never renders empty.
class MemberRedemptionsSection extends StatelessWidget {
  const MemberRedemptionsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: selectedGym,
      builder: (context, _) {
        final rewards = selectedGym.detail?.rewards;
        if (rewards == null || rewards.isEmpty) {
          return SubtitleSection(
            title: 'Reward Redemptions',
            child: _RedemptionsMessage(_emptyMessage()),
          );
        }
        final redemptions = <PendingRedemption>[
          for (var i = 0; i < kMemberRedemptionEvents.length; i++)
            _toRedemption(
              kMemberRedemptionEvents[i],
              rewards[i % rewards.length],
            ),
        ];
        return RedemptionsSection(
          redemptions: redemptions,
          title: 'Reward Redemptions',
        );
      },
    );
  }

  /// Null while the gym's rewards are still loading (renders a spinner).
  String? _emptyMessage() {
    if (selectedGym.gymId == null) {
      return 'Select a gym in the Theme tab to see redemptions.';
    }
    if (selectedGym.error != null) {
      return 'Could not reach the video service to load redemptions.';
    }
    return null;
  }

  PendingRedemption _toRedemption(MemberRedemptionEvent event, Reward reward) {
    return PendingRedemption(
      memberName: event.memberName,
      rewardTitle: reward.title,
      priceLabel: reward.priceLabel,
      pointsCost: reward.pointsCost,
      imageUrl: reward.imageUrl,
      code: event.code,
      requestedAt: event.requestedAt,
      approved: event.approved,
    );
  }
}

/// Loading (null message) / message chrome for the redemptions section.
class _RedemptionsMessage extends StatelessWidget {
  final String? message;

  const _RedemptionsMessage(this.message);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: message == null
          ? const SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: DesignConstants.primaryColor,
              ),
            )
          : Text(
              message!,
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
              textAlign: TextAlign.center,
            ),
    );
  }
}
