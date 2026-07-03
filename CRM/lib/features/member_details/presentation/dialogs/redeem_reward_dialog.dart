import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/rewards/data/models/reward_response.dart';
import 'package:crm/features/rewards/data/repositories/rewards_repository.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/billing_confirmation_dialog.dart';

/// Shows the gym's active rewards so staff can redeem one
/// on behalf of a member.
///
/// Fetches `GET /api/v1/rewards/?gym_id=<uuid>` via the
/// [RewardsRepository] (the same reward-catalog client the
/// Loyalty tab uses). On selection:
/// - If the member's [pointsBalance] >= reward's point_cost,
///   shows a standard confirmation then dispatches
///   [RedeemRewardForMemberRequested] with override=false.
/// - If balance < point_cost, shows an override warning
///   and on confirm re-dispatches with override=true
///   (drains balance to zero).
class RedeemRewardDialog extends StatefulWidget {
  final String gymId;
  final String memberId;
  final String memberName;
  final int pointsBalance;

  const RedeemRewardDialog({
    super.key,
    required this.gymId,
    required this.memberId,
    required this.memberName,
    required this.pointsBalance,
  });

  static Future<void> show({
    required BuildContext context,
    required String gymId,
    required String memberId,
    required String memberName,
    required int pointsBalance,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => MultiBlocProvider(
        providers: [
          BlocProvider.value(
            value: context.read<MemberDetailBloc>(),
          ),
          RepositoryProvider.value(
            value: context.read<RewardsRepository>(),
          ),
        ],
        child: RedeemRewardDialog(
          gymId: gymId,
          memberId: memberId,
          memberName: memberName,
          pointsBalance: pointsBalance,
        ),
      ),
    );
  }

  @override
  State<RedeemRewardDialog> createState() =>
      _RedeemRewardDialogState();
}

class _RedeemRewardDialogState
    extends State<RedeemRewardDialog> {
  late final Future<List<RewardResponse>> _rewardsFuture;

  @override
  void initState() {
    super.initState();
    _rewardsFuture = context
        .read<RewardsRepository>()
        .listRewards(widget.gymId);
  }

  Future<void> _onRewardTap(
    BuildContext context,
    RewardResponse reward,
  ) async {
    final bloc = context.read<MemberDetailBloc>();
    final canAfford =
        widget.pointsBalance >= reward.pointCost;

    if (canAfford) {
      // Standard confirmation flow.
      final confirmed = await BillingConfirmationDialog.show(
        context: context,
        title: 'Redeem reward',
        summary:
            'Redeem ${reward.title} for ${widget.memberName} '
            '(${reward.pointCost} pts)?',
        confirmLabel: 'Redeem',
        effects: [
          BillingEffect(
            icon: Symbols.star_sharp,
            text:
                '${reward.pointCost} points deducted from '
                '${widget.memberName}\'s balance.',
          ),
          BillingEffect(
            icon: Symbols.redeem_sharp,
            text: '${reward.title} marked as redeemed.',
          ),
        ],
      );
      if (!confirmed || !mounted) return;
      bloc.add(
        RedeemRewardForMemberRequested(
          rewardId: reward.rewardId,
          memberId: widget.memberId,
        ),
      );
    } else {
      // Override warning: balance insufficient.
      final confirmed = await BillingConfirmationDialog.show(
        context: context,
        title: 'Not enough points',
        summary:
            '${widget.memberName} doesn\'t have enough points '
            '(${widget.pointsBalance} / ${reward.pointCost} needed). '
            'Redeem anyway?',
        confirmLabel: 'Redeem anyway',
        confirmColor: DesignConstants.okYellow,
        warning:
            'This will drain ${widget.memberName}\'s balance to '
            'zero without covering the full point cost.',
        effects: [
          BillingEffect(
            icon: Symbols.star_sharp,
            text:
                'Balance drains to 0 (comp redemption).',
            iconColor: DesignConstants.okYellow,
          ),
        ],
      );
      if (!confirmed || !mounted) return;
      bloc.add(
        RedeemRewardForMemberRequested(
          rewardId: reward.rewardId,
          memberId: widget.memberId,
          allowOverride: true,
        ),
      );
    }

    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Redeem reward for ${widget.memberName}',
      body: FutureBuilder<List<RewardResponse>>(
        future: _rewardsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.all(
                DesignConstants.paddingBig,
              ),
              child: Center(child: AppSpinner()),
            );
          }
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(
                DesignConstants.spacingLarge,
              ),
              child: Text(
                'Failed to load rewards — please try again.',
                style: DesignConstants.p.copyWith(
                  color: DesignConstants.badRed,
                ),
              ),
            );
          }
          final rewards = (snapshot.data ?? [])
              .where((r) => r.isActive)
              .toList();
          if (rewards.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(
                DesignConstants.spacingLarge,
              ),
              child: Text(
                'No active rewards configured for this gym.',
                style: DesignConstants.p.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DesignConstants.spacingSmall,
            children: [
              Text(
                'Balance: ${widget.pointsBalance} pts',
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
              for (final r in rewards)
                _RewardPickerTile(
                  reward: r,
                  canAfford:
                      widget.pointsBalance >= r.pointCost,
                  onTap: () => _onRewardTap(context, r),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _RewardPickerTile extends StatelessWidget {
  final RewardResponse reward;
  final bool canAfford;
  final VoidCallback onTap;

  const _RewardPickerTile({
    required this.reward,
    required this.canAfford,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(
        DesignConstants.radiusSmall,
      ),
      child: Container(
        padding: const EdgeInsets.all(
          DesignConstants.spacingMedium,
        ),
        decoration: BoxDecoration(
          color: DesignConstants.backgroundColor,
          borderRadius: BorderRadius.circular(
            DesignConstants.radiusSmall,
          ),
        ),
        child: Row(
          spacing: DesignConstants.spacingMedium,
          children: [
            if (reward.imageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(
                  DesignConstants.radiusSmall,
                ),
                child: SizedBox(
                  width: DesignConstants.iconSizeBig,
                  height: DesignConstants.iconSizeBig,
                  child: Image.network(
                    reward.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Icon(
                      Symbols.redeem_sharp,
                    ),
                  ),
                ),
              )
            else
              Icon(
                Symbols.redeem_sharp,
                size: DesignConstants.iconSizeBig,
                color: DesignConstants.text3rd,
                weight: DesignConstants.iconWeight,
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: DesignConstants.spacingTiny,
                children: [
                  Text(
                    reward.title,
                    style: DesignConstants.h3,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${reward.pointCost} pts',
                    style: DesignConstants.pSmall.copyWith(
                      color: canAfford
                          ? DesignConstants.primaryColor
                          : DesignConstants.okYellow,
                    ),
                  ),
                ],
              ),
            ),
            if (!canAfford)
              Icon(
                Symbols.warning_sharp,
                size: DesignConstants.iconSizeMedium,
                color: DesignConstants.okYellow,
                weight: DesignConstants.iconWeight,
              ),
            Icon(
              Symbols.chevron_right_sharp,
              size: DesignConstants.iconSizeMedium,
              color: DesignConstants.text3rd,
              weight: DesignConstants.iconWeight,
            ),
          ],
        ),
      ),
    );
  }
}
