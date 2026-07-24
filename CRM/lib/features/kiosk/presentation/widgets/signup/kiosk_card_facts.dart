import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The two ticked facts under the card field: what happens to the card, and
/// what happens to the screen.
///
/// **The card line branches on the cart, and it has to.** A recurring
/// membership can only bill the payer's saved default, so the card IS kept and
/// the backend requires `set_default` — writing "only used for this signup"
/// there would be a lie the member finds out about on their next statement. A
/// purely one-time purchase is attach → pay → detach, and says so.
///
/// **And it names the PROFILE the card lands on.** "Saved" is only half the
/// promise; the other half is *to whom*, because that is the account a later
/// front-desk charge reads from. With no name to hand it degrades to the
/// unattributed sentence rather than to a wrong one.
class KioskCardFacts extends StatelessWidget {
  /// Whether anything in the cart bills again after today.
  final bool hasRecurring;

  /// The payer's full name — the profile this card attaches to. Empty when it
  /// is not known.
  final String payerName;

  const KioskCardFacts({
    super.key,
    required this.hasRecurring,
    this.payerName = '',
  });

  String get _cardLine {
    final who = payerName.trim();
    if (who.isEmpty) {
      return hasRecurring
          ? 'Saved so the membership keeps running — cancel any time at the '
              'front desk.'
          : 'Charged once. Not kept.';
    }
    return hasRecurring
        ? 'Saved to $who\'s profile so the membership keeps running — cancel '
            'any time at the front desk.'
        : 'Charged once, and not saved to $who\'s profile.';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        _Fact(text: _cardLine),
        const _Fact(
          text: 'This screen wipes itself if you walk away, so nothing of '
              'yours is left on the iPad.',
        ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  final String text;

  const _Fact({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Icon(
          Symbols.check_sharp,
          size: DesignConstants.iconSizeSmall,
          weight: DesignConstants.iconWeight,
          color: DesignConstants.goodGreen,
        ),
        Expanded(
          child: Text(
            text,
            style: DesignConstants.kioskCaption.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
        ),
      ],
    );
  }
}
