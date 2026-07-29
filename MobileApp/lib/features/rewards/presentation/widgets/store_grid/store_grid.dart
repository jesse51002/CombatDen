import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_bloc.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_state.dart';
import 'package:mobile_app/features/rewards/bloc/rewards_bloc.dart';
import 'package:mobile_app/features/rewards/bloc/rewards_event.dart';
import 'package:mobile_app/features/rewards/data/models/reward_item.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/reward_card.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/reward_redeem_dialog.dart';

/// Two-column points-store layout. Items zig-zag down (even indices in the
/// left column, odd in the right) so neighboring rows visually align.
class StoreGrid extends StatelessWidget {
  const StoreGrid({super.key, required this.items});

  final List<RewardItem> items;

  @override
  Widget build(BuildContext context) {
    final left = <RewardItem>[];
    final right = <RewardItem>[];
    for (var i = 0; i < items.length; i++) {
      (i.isEven ? left : right).add(items[i]);
    }
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: DesignConstants.screenHorizontalPadding,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingLarge,
        children: [
          Expanded(child: _StoreColumn(items: left)),
          Expanded(child: _StoreColumn(items: right)),
        ],
      ),
    );
  }
}

class _StoreColumn extends StatelessWidget {
  const _StoreColumn({required this.items});

  final List<RewardItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        for (final item in items) _StoreRewardCard(item: item),
      ],
    );
  }
}

/// One store card. The "Redeem" CTA is disabled when the member can't afford
/// the reward (its cost exceeds the balance on the shared [MemberProfileBloc]);
/// otherwise it opens the confirm dialog and, on confirm, dispatches the redeem.
class _StoreRewardCard extends StatelessWidget {
  const _StoreRewardCard({required this.item});

  final RewardItem item;

  Future<void> _redeem(BuildContext context) async {
    final bloc = context.read<RewardsBloc>();
    final confirmed = await RewardRedeemDialog.show(
      context,
      imageUrl: item.imageUrl,
      title: item.title,
      priceLabel: item.priceLabel,
      pointsCost: item.pointCost,
    );
    if (confirmed == true) {
      bloc.add(RewardsRedeemRequested(rewardId: item.rewardId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MemberProfileBloc, MemberProfileState>(
      builder: (context, state) {
        final balance = state.profile?.retention.pointsBalance;
        final affordable = balance != null && item.pointCost <= balance;
        return RewardCard(
          imageUrl: item.imageUrl,
          title: item.title,
          priceLabel: item.priceLabel,
          pointsCost: item.pointCost,
          buttonText: 'Redeem',
          onPressed: affordable ? () => _redeem(context) : null,
        );
      },
    );
  }
}
