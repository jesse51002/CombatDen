import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/reward_card/reward_card.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';

// Static prototype code — every reward shows the same one for now.
const String _kVerificationCode = 'TXR-3K9P';

/// Dialog shown when a member taps the CTA on a reward card. Echoes the
/// card's image / title / points, then surfaces the bold verification
/// code, the front-desk instructions, and a disabled "Waiting for Admin
/// Approval" button.
class RewardRedeemDialog extends StatelessWidget {
  const RewardRedeemDialog({
    super.key,
    required this.imageAsset,
    required this.title,
    required this.priceLabel,
    required this.pointsCost,
  });

  final String imageAsset;
  final String title;
  final String priceLabel;
  final int pointsCost;

  /// Convenience: open this dialog from any reward card's `onPressed`.
  static Future<void> show(
    BuildContext context, {
    required String imageAsset,
    required String title,
    required String priceLabel,
    required int pointsCost,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => RewardRedeemDialog(
        imageAsset: imageAsset,
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
            _DialogHeader(onClose: () => Navigator.of(context).pop()),
            RewardImageHero(
              imageAsset: imageAsset,
              priceLabel: priceLabel,
              borderRadius: BorderRadius.circular(
                DesignConstants.radiusSmall,
              ),
            ),
            _TitleAndCost(title: title, pointsCost: pointsCost, brand: brand),
            _VerificationBlock(brand: brand),
            Text(
              'Show this code to the front desk or your coach to redeem.',
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
              textAlign: TextAlign.center,
            ),
            AppPrimaryButton(
              text: 'Waiting for Admin Approval',
              fullWidth: true,
              borderRadius: DesignConstants.radiusBig,
              textStyle: DesignConstants.h3,
              onPressed: null,
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

class _VerificationBlock extends StatelessWidget {
  const _VerificationBlock({required this.brand});

  final Color brand;

  @override
  Widget build(BuildContext context) {
    final eyebrow = DesignConstants.pSmall.copyWith(
      color: DesignConstants.text2nd,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.24 * (DesignConstants.pSmall.fontSize ?? 11),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text('VERIFICATION CODE', style: eyebrow, textAlign: TextAlign.center),
        Text(
          _kVerificationCode,
          style: DesignConstants.big2.copyWith(
            color: brand,
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
