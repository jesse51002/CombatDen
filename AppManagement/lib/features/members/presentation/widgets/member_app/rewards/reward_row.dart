import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/data/mock_member_app_preview.dart';
import 'package:app_management/shared/widgets/app_outline_button.dart';

/// One configurable reward inside a points tier.
///
/// Layout: brand + name + discount on the left, circular product image
/// on the right, with an "Edit" + "Remove" stack of buttons further to
/// the right when this is a configured reward.
class RewardRow extends StatelessWidget {
  final RewardItem reward;

  const RewardRow({super.key, required this.reward});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.paddingBig,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: DesignConstants.spacingBig,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DesignConstants.spacingMedium,
              children: [
                Text(reward.brand, style: DesignConstants.h3),
                Text(reward.name, style: DesignConstants.p),
                Text(
                  reward.discount,
                  style: DesignConstants.p.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
              ],
            ),
          ),
          _RewardImage(asset: reward.imageAsset),
          SizedBox(
            width: 220,
            child: Column(
              spacing: DesignConstants.spacingLarge,
              children: [
                AppOutlineButton(
                  text: 'Edit',
                  fullWidth: true,
                  onPressed: () =>
                      debugPrint('TODO: in-preview action'),
                ),
                _RemoveButton(
                  onPressed: () =>
                      debugPrint('TODO: in-preview action'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RewardImage extends StatelessWidget {
  final String asset;
  const _RewardImage({required this.asset});

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        height: 100,
        width: 100,
        child: Image.asset(asset, fit: BoxFit.cover),
      ),
    );
  }
}

class _RemoveButton extends StatelessWidget {
  final VoidCallback? onPressed;
  const _RemoveButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: DesignConstants.redDark,
          foregroundColor: DesignConstants.text,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: DesignConstants.paddingSmall,
            vertical: DesignConstants.spacingMedium,
          ),
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(DesignConstants.radiusBig),
          ),
        ),
        child: Text(
          'Remove',
          style: DesignConstants.h3,
        ),
      ),
    );
  }
}
