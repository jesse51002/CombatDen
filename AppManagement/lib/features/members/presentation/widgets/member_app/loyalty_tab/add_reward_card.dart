import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/data/mock_loyalty.dart';
import 'package:app_management/shared/widgets/app_outline_button.dart';
import 'package:app_management/shared/widgets/section_card.dart';

/// One starter in the "Add your own" grid: a reward template the admin
/// can drop into the store and then configure.
class AddRewardCard extends StatelessWidget {
  final RewardTemplate template;

  const AddRewardCard({super.key, required this.template});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            spacing: DesignConstants.spacingLarge,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: DesignConstants.spacingSmall,
                  children: [
                    Text(template.title, style: DesignConstants.h3),
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
                  height: 72,
                  width: 72,
                  child: Image.asset(template.imageAsset, fit: BoxFit.cover),
                ),
              ),
            ],
          ),
          AppOutlineButton(
            text: 'Add',
            fullWidth: true,
            onPressed: () => debugPrint('TODO: add reward template'),
          ),
        ],
      ),
    );
  }
}
