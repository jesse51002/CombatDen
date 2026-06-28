import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/members/data/mock_loyalty.dart';
import 'package:crm/features/rewards/presentation/dialogs/reward_form_dialog.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/section_card.dart';

/// One starter in the "Add your own" grid.
///
/// In the admin context (`gymId != null`) the Add button opens the reward
/// create form pre-filled with the template's suggested values. In the
/// template preview (`gymId == null`) the button is a no-op (no gym to
/// write to).
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
                  height: DesignConstants.rewardAvatarSize,
                  width: DesignConstants.rewardAvatarSize,
                  child: Image.asset(template.imageAsset, fit: BoxFit.cover),
                ),
              ),
            ],
          ),
          AppOutlineButton(
            text: 'Add',
            fullWidth: true,
            onPressed: selectedGym.gymId != null
                ? () => RewardFormDialog.show(
                    context,
                    prefillTitle: template.title,
                    prefillPointCost: template.suggestedPointCost,
                    prefillPriceLabel: template.suggestedPriceLabel,
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
