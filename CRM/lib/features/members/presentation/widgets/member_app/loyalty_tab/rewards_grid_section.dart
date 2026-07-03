import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/members/data/gym_detail.dart';
import 'package:crm/features/members/presentation/widgets/member_app/loyalty_tab/admin_reward_card.dart';
import 'package:crm/features/members/presentation/widgets/member_app/loyalty_tab/reward_image_hero.dart';
import 'package:crm/features/rewards/bloc/rewards_bloc.dart';
import 'package:crm/features/rewards/bloc/rewards_state.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/fill_grid.dart';
import 'package:crm/shared/widgets/section_card.dart';
import 'package:crm/shared/widgets/subtitle_section.dart';

/// "Rewards Store" section.
///
/// **Admin path** (`selectedGym.gymId != null`): bloc-backed live catalog
/// from the FastApiBackend with Edit / Remove CRUD actions.
///
/// **Template path** (`gymId == null`): read-only display from
/// `selectedGym.detail.rewards` (VideoService data), no CRUD.
class RewardsGridSection extends StatelessWidget {
  const RewardsGridSection({super.key});

  @override
  Widget build(BuildContext context) {
    // Branch on the real-gym discriminator (see CLAUDE.md video integration).
    final gymId = selectedGym.gymId;
    if (gymId != null) {
      return const _LiveRewardsGrid();
    }
    return const _TemplateRewardsGrid();
  }
}

// ── Admin path (real gym, bloc-backed) ─────────────────────────────────────

class _LiveRewardsGrid extends StatelessWidget {
  const _LiveRewardsGrid();

  @override
  Widget build(BuildContext context) {
    return SubtitleSection(
      title: 'Rewards Store',
      child: BlocBuilder<RewardsBloc, RewardsState>(
        builder: (context, state) {
          if (state.catalogStatus == RewardsCatalogStatus.initial ||
              state.catalogStatus == RewardsCatalogStatus.loading) {
            return const _RewardsMessage(null);
          }
          if (state.catalogStatus == RewardsCatalogStatus.error) {
            return _RewardsMessage(
              state.catalogError ?? 'Could not load rewards.',
            );
          }
          if (state.rewards.isEmpty) {
            return const _RewardsMessage(
              'No rewards yet. Add one below.',
            );
          }
          return FillGrid(
            minItemWidth: 220,
            children: [
              for (final r in state.rewards) AdminRewardCard(reward: r),
            ],
          );
        },
      ),
    );
  }
}

// ── Template path (read-only, VideoService) ────────────────────────────────

class _TemplateRewardsGrid extends StatelessWidget {
  const _TemplateRewardsGrid();

  @override
  Widget build(BuildContext context) {
    return SubtitleSection(
      title: 'Rewards Store',
      child: ListenableBuilder(
        listenable: selectedGym,
        builder: (context, _) {
          if (selectedGym.videoGymId == null) {
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
              for (final r in rewards) _TemplateRewardCard(reward: r),
            ],
          );
        },
      ),
    );
  }
}

/// Read-only display card for VideoService template rewards (no CRUD).
class _TemplateRewardCard extends StatelessWidget {
  final Reward reward;

  const _TemplateRewardCard({required this.reward});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RewardImageHero(
            imageUrl: reward.imageUrl,
            priceLabel: reward.priceLabel,
          ),
          Padding(
            padding: const EdgeInsets.all(DesignConstants.paddingSmall),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: DesignConstants.spacingMedium,
              children: [
                SizedBox(
                  height: DesignConstants.rewardCardTitleHeight,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Text(
                      reward.title,
                      style: DesignConstants.h2,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                Text(
                  '${formatRewardPoints(reward.pointsCost)} pts',
                  style: DesignConstants.h2.copyWith(
                    color: DesignConstants.primaryColor,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
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
            ? const AppSpinner()
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
