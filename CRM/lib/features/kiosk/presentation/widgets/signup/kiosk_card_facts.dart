import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The ticked reassurances under the card field.
///
/// **Everything here is good news, and that is what the green check means.**
/// What HAPPENS to the card — it is saved to a named profile and it replaces
/// whatever was there — is a consequence the member has to register, not a
/// reassurance, so it rides the warm inline notice above this block instead.
/// A green tick beside "we are replacing your card" would be actively
/// misleading.
class KioskCardFacts extends StatelessWidget {
  /// Whether anything in the cart bills again after today. Only a thing that
  /// keeps billing can be cancelled, so the line is conditional on it.
  final bool hasRecurring;

  const KioskCardFacts({super.key, required this.hasRecurring});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        if (hasRecurring)
          const _Fact(text: 'Cancel any time at the front desk.'),
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
