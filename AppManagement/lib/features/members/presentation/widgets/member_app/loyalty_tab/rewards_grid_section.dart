import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/core/state/selected_gym.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/loyalty_tab/admin_reward_card.dart';
import 'package:app_management/shared/widgets/fill_grid.dart';
import 'package:app_management/shared/widgets/section_card.dart';
import 'package:app_management/shared/widgets/subtitle_section.dart';

/// "Rewards Store" section: the points-based rewards members can redeem,
/// laid out as a reflowing grid of [AdminRewardCard]s. Driven live by the
/// selected gym (held in [selectedGym] memory) so the store follows the gym.
class RewardsGridSection extends StatelessWidget {
  const RewardsGridSection({super.key});

  @override
  Widget build(BuildContext context) {
    return SubtitleSection(
      title: 'Rewards Store',
      child: ListenableBuilder(
        listenable: selectedGym,
        builder: (context, _) {
          if (selectedGym.gymId == null) {
            return const _RewardsMessage(
              'Select a gym in the Theme tab to see its rewards.',
            );
          }
          final detail = selectedGym.detail;
          if (detail == null) {
            return _RewardsMessage(
              selectedGym.error != null
                  ? 'Could not reach the video service. Start it and reopen '
                        'this tab to load this gym\'s rewards.'
                  : null,
            );
          }
          final rewards = detail.rewards;
          if (rewards.isEmpty) {
            return const _RewardsMessage('This gym has no rewards yet.');
          }
          return FillGrid(
            minItemWidth: 220,
            children: [
              for (final reward in rewards) AdminRewardCard(reward: reward),
            ],
          );
        },
      ),
    );
  }
}

/// Loading (null message) / error / empty chrome for the rewards store.
class _RewardsMessage extends StatelessWidget {
  final String? message;

  const _RewardsMessage(this.message);

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.all(DesignConstants.paddingBig),
      child: Center(
        child: message == null
            ? SizedBox(
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
      ),
    );
  }
}
