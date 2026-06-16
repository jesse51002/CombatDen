import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/custom_card_capture.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';

/// Payment-step section letting staff pay the ONE-TIME charge
/// with a card entered now instead of the saved default.
/// Shown only when the cart has a one-time / trial membership
/// and the run isn't cash. Recurring memberships always bill
/// the saved card — the clarifier says so on a mixed cart.
class OneTimeCardSection extends StatelessWidget {
  final CustomCardCapture? customCard;
  final bool hasRecurring;
  final VoidCallback onAddOrChange;
  final VoidCallback onRemove;

  const OneTimeCardSection({
    super.key,
    required this.customCard,
    required this.hasRecurring,
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
        Text(
          'One-time purchase card',
          style: DesignConstants.h3,
        ),
        if (card == null)
          _AddCardPrompt(onAddOrChange: onAddOrChange)
        else
          _CapturedCardTile(
            card: card,
            onChange: onAddOrChange,
            onRemove: onRemove,
          ),
        if (hasRecurring)
          Text(
            'Recurring memberships always bill the saved '
            'card on file.',
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
      ],
    );
  }
}

class _AddCardPrompt extends StatelessWidget {
  final VoidCallback onAddOrChange;

  const _AddCardPrompt({required this.onAddOrChange});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text(
          'Charge the one-time items to a different card '
          'without saving it.',
          style: DesignConstants.pSmall.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
        AppOutlineButton(
          text: 'Use a different card',
          borderRadius: DesignConstants.radiusSmall,
          icon: const Icon(Symbols.add_card_sharp),
          onPressed: onAddOrChange,
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
                  card.setAsDefault
                      ? 'Will become the default card'
                      : 'One-time use',
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
