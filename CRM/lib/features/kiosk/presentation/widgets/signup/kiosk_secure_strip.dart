import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The card step's trust strip: a padlock disc beside two lines that say who
/// does and does not see the card number.
///
/// It sits ABOVE the field on purpose. A member is deciding whether to type
/// sixteen digits into a lobby iPad, and the answer to that has to arrive
/// before the box does, not underneath it.
///
/// The second line names the GYM, because "CombatDen never sees it" means
/// nothing to someone standing in Iron Den. With no gym name known it degrades
/// to naming the gym generically rather than inventing one — a wrong gym name
/// on a member-facing screen is worse than none.
class KioskSecureStrip extends StatelessWidget {
  final String? gymName;

  const KioskSecureStrip({super.key, this.gymName});

  /// "Iron Den never sees your card number, and neither does this iPad."
  String get _detail {
    final gym = gymName?.trim() ?? '';
    final who = gym.isEmpty ? 'This gym' : gym;
    return '$who never sees your card number, and neither does this iPad.';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.accentSoft,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      ),
      child: Row(
        spacing: DesignConstants.spacingLarge,
        children: [
          const _LockDisc(),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: DesignConstants.spacingSmall,
              children: [
                Text(
                  'Encrypted and sent straight to Stripe',
                  style: DesignConstants.kioskLabel,
                ),
                Text(
                  _detail,
                  style: DesignConstants.kioskCaption.copyWith(
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

class _LockDisc extends StatelessWidget {
  const _LockDisc();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignConstants.spacingMedium),
      decoration: BoxDecoration(
        color: DesignConstants.primaryColor,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Symbols.lock_sharp,
        size: DesignConstants.iconSizeLarge,
        weight: DesignConstants.iconWeight,
        color: DesignConstants.onAccent,
      ),
    );
  }
}
