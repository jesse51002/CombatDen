import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/card_on_file.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';

/// The payment step's card wallet.
///
// TODO(known placeholder): this multi-card wallet is a
// placeholder with fake data — stored multiple payment
// methods are NOT a backend feature yet (required before
// launch; the backend ships separately). Today the backend
// always charges the payer's single card on file, and "Add
// new" runs the existing update-card flow, which REPLACES
// the card. DELETE this comment (and the fake entry) when
// the payment-methods backend is implemented.
class CardWalletSection extends StatelessWidget {
  /// The payer's real card on file (the one the backend
  /// actually charges), or null when none is saved.
  final CardOnFile? cardOnFile;
  final VoidCallback onAddNew;

  const CardWalletSection({
    super.key,
    required this.cardOnFile,
    required this.onAddNew,
  });

  @override
  Widget build(BuildContext context) {
    final card = cardOnFile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingSmall,
      children: [
        if (card != null)
          _WalletCardTile(
            label:
                '${card.brand} ···· ${card.lastFour}',
            sublabel: 'Expires '
                '${card.expMonth}/${card.expYear} · '
                'card on file',
            selected: true,
          )
        else
          Text(
            'No card on file — add one below or '
            'settle in cash.',
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.okYellow,
            ),
          ),
        // Fake wallet entry (see the class-level known
        // placeholder comment): demonstrates the multi-card
        // list; not selectable, never charged.
        const _WalletCardTile(
          label: 'Visa ···· 4242',
          sublabel: 'Example card — multi-card wallets '
              'are coming soon',
          selected: false,
          disabled: true,
        ),
        AppOutlineButton(
          text: 'Add new card',
          borderRadius: DesignConstants.radiusSmall,
          onPressed: onAddNew,
        ),
      ],
    );
  }
}

class _WalletCardTile extends StatelessWidget {
  final String label;
  final String sublabel;
  final bool selected;
  final bool disabled;

  const _WalletCardTile({
    required this.label,
    required this.sublabel,
    required this.selected,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final tile = Container(
      padding: const EdgeInsets.all(
        DesignConstants.spacingMedium,
      ),
      decoration: BoxDecoration(
        color: selected
            ? DesignConstants.primaryColor10
            : DesignConstants.backgroundColor,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
        border: Border.all(
          color: selected
              ? DesignConstants.primaryColor
              : DesignConstants.divider,
          width: selected ? 2 : 1,
        ),
      ),
      child: Row(
        spacing: DesignConstants.spacingMedium,
        children: [
          Icon(
            Symbols.credit_card_sharp,
            weight: DesignConstants.iconWeight,
            size: DesignConstants.iconSizeMedium,
            color: selected
                ? DesignConstants.primaryColor
                : DesignConstants.text2nd,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              spacing: DesignConstants.spacingTiny,
              children: [
                Text(label, style: DesignConstants.p),
                Text(
                  sublabel,
                  style:
                      DesignConstants.pSmall.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            selected
                ? Symbols.radio_button_checked_sharp
                : Symbols
                    .radio_button_unchecked_sharp,
            weight: DesignConstants.iconWeight,
            size: DesignConstants.iconSizeLarge,
            color: selected
                ? DesignConstants.primaryColor
                : DesignConstants.text3rd,
          ),
        ],
      ),
    );
    return disabled
        ? Opacity(opacity: 0.5, child: tile)
        : tile;
  }
}
