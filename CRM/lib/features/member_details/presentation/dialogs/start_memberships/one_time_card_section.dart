import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/custom_card_capture.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';

/// Payment-step section letting staff pay the ONE-TIME charge
/// with a card entered now instead of the saved default.
/// Shown only for a PURELY one-time / trial cart that isn't
/// cash — a cart with any recurring membership never offers
/// it (recurring always bills the saved card).
class OneTimeCardSection extends StatelessWidget {
  final CustomCardCapture? customCard;
  final VoidCallback onAddOrChange;
  final VoidCallback onRemove;

  const OneTimeCardSection({
    super.key,
    required this.customCard,
    required this.onAddOrChange,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final card = customCard;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingTiny,
          children: [
            Text(
              'One-off card for this purchase',
              style: DesignConstants.h3,
            ),
            Text(
              'Charge just this one-time purchase to a '
              'different card. It isn’t saved and isn’t '
              'used for recurring memberships.',
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          ],
        ),
        if (card == null)
          Align(
            alignment: Alignment.centerLeft,
            child: AppOutlineButton(
              text: 'Use a one-off card',
              borderRadius: DesignConstants.radiusSmall,
              icon: const Icon(Symbols.add_card_sharp),
              onPressed: onAddOrChange,
            ),
          )
        else
          _CapturedCardTile(
            card: card,
            onChange: onAddOrChange,
            onRemove: onRemove,
          ),
      ],
    );
  }
}

class _CapturedCardTile extends StatelessWidget {
  final CustomCardCapture card;
  final VoidCallback onChange;
  final VoidCallback onRemove;

  const _CapturedCardTile({
    required this.card,
    required this.onChange,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(
        DesignConstants.paddingSmall,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.primaryColor10,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
        border: Border.all(
          color: DesignConstants.primaryColor,
          width: 2,
        ),
      ),
      child: Row(
        spacing: DesignConstants.spacingMedium,
        children: [
          Icon(
            Symbols.credit_card_sharp,
            weight: DesignConstants.iconWeight,
            size: DesignConstants.iconSizeMedium,
            color: DesignConstants.primaryColor,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              spacing: DesignConstants.spacingTiny,
              children: [
                Text(
                  card.display,
                  style: DesignConstants.p,
                ),
                Text(
                  'One-time use · not saved',
                  style: DesignConstants.pSmall.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
              ],
            ),
          ),
          AppOutlineButton(
            text: 'Change',
            borderRadius: DesignConstants.radiusSmall,
            textStyle: DesignConstants.pSmall,
            onPressed: onChange,
          ),
          AppOutlineButton(
            text: 'Remove',
            borderRadius: DesignConstants.radiusSmall,
            textStyle: DesignConstants.pSmall,
            borderColor: DesignConstants.badRed,
            textColor: DesignConstants.badRed,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
