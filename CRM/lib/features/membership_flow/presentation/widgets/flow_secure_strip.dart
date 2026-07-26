import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';

/// The card step's trust strip: a padlock disc beside two lines that say who
/// does and does not see the card number.
///
/// It promises exactly two things — the number is encrypted straight to Stripe,
/// and neither the named gym nor this iPad sees it. It sits ABOVE the field,
/// because a member deciding whether to type sixteen digits into a lobby iPad
/// needs that answer before the box, not underneath it.
///
/// The second line names the GYM ("CombatDen never sees it" means nothing to
/// someone standing in Iron Den) and degrades to "This gym" rather than
/// inventing one: a wrong gym name on a member-facing screen is worse than
/// none.
class FlowSecureStrip extends StatelessWidget {
  final String? gymName;

  const FlowSecureStrip({super.key, this.gymName});

  /// "Iron Den never sees your card number, and neither does this iPad."
  String get _detail {
    final gym = gymName?.trim() ?? '';
    final who = gym.isEmpty ? 'This gym' : gym;
    return '$who never sees your card number, and neither does this iPad.';
  }

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
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
                  style: scale.label,
                ),
                Text(
                  _detail,
                  style: scale.caption.copyWith(
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
