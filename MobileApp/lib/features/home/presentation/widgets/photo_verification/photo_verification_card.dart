import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/shared/widgets/buttons/app_outline_button.dart';

class PhotoVerificationCard extends StatelessWidget {
  const PhotoVerificationCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: DesignConstants.primaryColor25,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      ),
      padding: EdgeInsets.all(DesignConstants.paddingSmall),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          const _InfoRow(),
          AppOutlineButton(
            text: 'Complete Photo Verification',
            fullWidth: true,
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingLarge,
      children: [
        Expanded(
          flex: 4,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingLarge,
            children: [
              Text('Earn Rewards from Gyming', style: DesignConstants.h3),
              Text(
                'Complete photo verification to enable rewards like '
                'gear discounts and swag from gyming.',
                style: DesignConstants.p.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 3,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 120),
            child: Image.asset(
              'assets/images/photo_verification_gear.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
      ],
    );
  }
}
