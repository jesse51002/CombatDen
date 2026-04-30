import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/data/mock_member_app_preview.dart';
import 'package:app_management/shared/widgets/app_outline_button.dart';
import 'package:app_management/shared/widgets/section_card.dart';

/// One tile in the "Add more rewards" 2x2 grid — a reward template the
/// admin can add to the live store.
class AddRewardCard extends StatelessWidget {
  final RewardTemplate template;

  const AddRewardCard({super.key, required this.template});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        spacing: DesignConstants.spacingLarge,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            spacing: DesignConstants.spacingSmall,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: DesignConstants.spacingMedium,
                  children: [
                    Text(template.brand, style: DesignConstants.h3),
                    Text(template.title, style: DesignConstants.p),
                    if (template.subtitle != null)
                      Text(
                        template.subtitle!,
                        style: DesignConstants.p.copyWith(
                          color: DesignConstants.text2nd,
                        ),
                      ),
                  ],
                ),
              ),
              ClipOval(
                child: SizedBox(
                  height: 100,
                  width: 100,
                  child: Image.asset(
                    template.imageAsset,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ],
          ),
          AppOutlineButton(
            text: 'Add',
            fullWidth: true,
            onPressed: () => debugPrint('TODO: in-preview action'),
          ),
        ],
      ),
    );
  }
}
