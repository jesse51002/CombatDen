import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

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
              _Thumbnail(template: template),
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

/// The starter's grid thumbnail: a circular photo for the presets, or a
/// sapphire-tinted gift-box icon for the [RewardTemplate.isCustom] starter,
/// so "make your own" reads distinctly from the photographic presets.
class _Thumbnail extends StatelessWidget {
  final RewardTemplate template;

  const _Thumbnail({required this.template});

  @override
  Widget build(BuildContext context) {
    const size = DesignConstants.rewardAvatarSize;

    if (template.isCustom) {
      return Container(
        height: size,
        width: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: DesignConstants.primaryColor10,
          border: Border.all(
            color: DesignConstants.primaryColor25,
            width: DesignConstants.buttonBorder,
          ),
        ),
        child: Center(
          child: Icon(
            Symbols.card_giftcard_sharp,
            size: DesignConstants.iconSizeBig,
            color: DesignConstants.primaryColor,
            weight: DesignConstants.iconWeight,
          ),
        ),
      );
    }

    return ClipOval(
      child: SizedBox(
        height: size,
        width: size,
        child: Image.asset(template.imageAsset!, fit: BoxFit.cover),
      ),
    );
  }
}
