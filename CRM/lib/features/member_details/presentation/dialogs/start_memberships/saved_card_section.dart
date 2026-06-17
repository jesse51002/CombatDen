import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/card_on_file.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';

/// The payment step's **"Card on file"** option: the payer's single saved
/// default card (what the backend charges for recurring memberships, and for
/// a one-time purchase unless a one-off card is used) plus a button to add or
/// replace it. There is no multi-card wallet — one saved default card per
/// payer. Pairs with [OneTimeCardSection] to present two distinct choices on a
/// one-time cart: edit this saved card, or use a one-off card just for today.
class SavedCardSection extends StatelessWidget {
  /// The payer's real card on file, or null when none is saved.
  final CardOnFile? cardOnFile;

  /// Whether the cart has a recurring membership — drives the subtitle so it
  /// names what this saved card actually pays for this purchase.
  final bool hasRecurring;
  final VoidCallback onAddOrEdit;

  const SavedCardSection({
    super.key,
    required this.cardOnFile,
    required this.hasRecurring,
    required this.onAddOrEdit,
  });

  String get _subtitle {
    if (cardOnFile == null) {
      return 'No saved card yet — add one or settle in cash.';
    }
    return hasRecurring
        ? 'Every recurring membership is billed to this '
            'saved card. Editing it re-bills ALL of them to '
            'the new card going forward — not just this '
            'purchase.'
        : 'This purchase is billed to the saved card unless '
            'you use a one-off card below. Editing the saved '
            'card re-bills EVERY recurring membership the '
            'payer has to the new card — not just today.';
  }

  @override
  Widget build(BuildContext context) {
    final card = cardOnFile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingTiny,
          children: [
            Text('Card on file', style: DesignConstants.h3),
            Text(
              _subtitle,
              // Full text colour (not muted) on the card case —
              // this carries a global side effect, so it must read.
              style: DesignConstants.pSmall.copyWith(
                color: card == null
                    ? DesignConstants.okYellow
                    : DesignConstants.text,
              ),
            ),
          ],
        ),
        if (card != null) _SavedCardTile(card: card),
        Align(
          alignment: Alignment.centerLeft,
          child: AppOutlineButton(
            text: card == null
                ? 'Add card'
                : 'Edit card on file',
            borderRadius: DesignConstants.radiusSmall,
            icon: const Icon(Symbols.credit_card_sharp),
            onPressed: onAddOrEdit,
          ),
        ),
      ],
    );
  }
}

class _SavedCardTile extends StatelessWidget {
  final CardOnFile card;

  const _SavedCardTile({required this.card});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(
        DesignConstants.paddingSmall,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.backgroundColor,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
        border: Border.all(color: DesignConstants.divider),
      ),
      child: Row(
        spacing: DesignConstants.spacingMedium,
        children: [
          Icon(
            Symbols.credit_card_sharp,
            weight: DesignConstants.iconWeight,
            size: DesignConstants.iconSizeMedium,
            color: DesignConstants.text2nd,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DesignConstants.spacingTiny,
              children: [
                Text(
                  '${card.brand} ···· ${card.lastFour}',
                  style: DesignConstants.p,
                ),
                Text(
                  'Expires ${card.expMonth}/${card.expYear}'
                  ' · card on file',
                  style: DesignConstants.pSmall.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
