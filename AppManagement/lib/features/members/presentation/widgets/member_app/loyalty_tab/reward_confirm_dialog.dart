import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/data/mock_loyalty.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/loyalty_tab/reward_image_hero.dart';
import 'package:app_management/shared/widgets/app_dialog/app_dialog.dart';
import 'package:app_management/shared/widgets/app_primary_button.dart';
import 'package:app_management/shared/widgets/info_row.dart';

/// Admin-side counterpart to the member's redeem dialog. Echoes the
/// reward art, points, and who requested it, shows the verification code,
/// and asks the admin to check it matches the member's phone before
/// marking the transaction completed.
class RewardConfirmDialog extends StatelessWidget {
  final PendingRedemption redemption;

  const RewardConfirmDialog({super.key, required this.redemption});

  static Future<void> show(BuildContext context, PendingRedemption redemption) {
    return showDialog<void>(
      context: context,
      builder: (_) => RewardConfirmDialog(redemption: redemption),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = redemption;
    return AppDialog(
      title: '',
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          RewardImageHero(
            imageAsset: r.imageAsset,
            priceLabel: r.priceLabel,
            borderRadius: BorderRadius.circular(
              DesignConstants.radiusSmall,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingSmall,
            children: [
              Text(
                r.rewardTitle,
                style: DesignConstants.h1,
                textAlign: TextAlign.center,
              ),
              Text(
                '${formatRewardPoints(r.pointsCost)} pts',
                style: DesignConstants.h2.copyWith(
                  color: DesignConstants.primaryColor,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingSmall,
            children: [
              InfoRow(label: 'Member', value: r.memberName),
              InfoRow(label: 'Requested', value: r.requestedAt),
            ],
          ),
          _VerificationBlock(code: r.code),
          Text(
            "Make sure this matches the code on the member's phone "
            'before confirming.',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text2nd,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: AppPrimaryButton(
        text: 'Confirm Transaction Completed',
        fullWidth: true,
        onPressed: () => Navigator.of(context).pop(),
      ),
    );
  }
}

class _VerificationBlock extends StatelessWidget {
  final String code;

  const _VerificationBlock({required this.code});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text(
          'VERIFICATION CODE',
          style: DesignConstants.pSmallBold.copyWith(
            color: DesignConstants.text2nd,
          ),
          textAlign: TextAlign.center,
        ),
        Text(
          code,
          style: DesignConstants.big2Bold.copyWith(
            color: DesignConstants.primaryColor,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
