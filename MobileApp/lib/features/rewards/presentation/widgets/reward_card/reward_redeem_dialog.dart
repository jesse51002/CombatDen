import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/reward_card.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';

/// Confirmation dialog shown when a member taps "Redeem" on a store reward.
/// Echoes the card's image / title / points, states the debit-on-request
/// model, and offers a "Redeem" button. Confirming pops `true`; the caller —
/// which holds the [RewardsBloc] — dispatches the redeem, and the screen shows
/// the pending-approval confirmation on success.
class RewardRedeemDialog extends StatelessWidget {
  const RewardRedeemDialog({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.priceLabel,
    required this.pointsCost,
  });

  final String imageUrl;
  final String title;
  final String priceLabel;
  final int pointsCost;

  /// Open the dialog; resolves to `true` when the member confirms the redeem,
  /// `false` / null when they dismiss it.
  static Future<bool?> show(
    BuildContext context, {
    required String imageUrl,
    required String title,
    required String priceLabel,
    required int pointsCost,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => RewardRedeemDialog(
        imageUrl: imageUrl,
        title: title,
        priceLabel: priceLabel,
        pointsCost: pointsCost,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brand = DesignConstants.primaryColor;
    return Dialog(
      backgroundColor: DesignConstants.popup,
      insetPadding: EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingBig,
        vertical: DesignConstants.spacingBig,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      ),
      child: Padding(
        padding: EdgeInsets.all(DesignConstants.paddingSmall),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingLarge,
          children: [
            _DialogHeader(onClose: () => Navigator.of(context).pop(false)),
            RewardImageHero(
              imageUrl: imageUrl,
              priceLabel: priceLabel,
              borderRadius: BorderRadius.circular(
                DesignConstants.radiusSmall,
              ),
            ),
            _TitleAndCost(title: title, pointsCost: pointsCost, brand: brand),
            Text(
              'Redeeming spends your points now. Show up at the gym — staff '
              'approve and hand it over.',
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
              textAlign: TextAlign.center,
            ),
            AppPrimaryButton(
              text: 'Redeem',
              fullWidth: true,
              borderRadius: DesignConstants.radiusBig,
              textStyle: DesignConstants.h3,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onClose,
        child: Icon(
          Symbols.close_sharp,
          color: DesignConstants.text2nd,
          weight: DesignConstants.iconWeight,
          size: DesignConstants.iconSizeMd,
        ),
      ),
    );
  }
}

class _TitleAndCost extends StatelessWidget {
  const _TitleAndCost({
    required this.title,
    required this.pointsCost,
    required this.brand,
  });

  final String title;
  final int pointsCost;
  final Color brand;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text(
          title,
          style: DesignConstants.h1,
          textAlign: TextAlign.center,
        ),
        Text(
          '${formatRewardPoints(pointsCost)} pts',
          style: DesignConstants.h2.copyWith(color: brand),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
