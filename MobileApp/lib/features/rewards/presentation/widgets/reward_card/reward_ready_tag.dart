import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_app/core/design_constants.dart';

/// "Ready" — the mark on a reward photo the member can redeem right now.
///
/// It lives beside [RewardPriceTag] rather than in `shared/widgets/` because
/// it is that tag's sibling: same padding, same radius, same pin family, same
/// domain. Keeping the two reward tags in one folder is what stops them
/// drifting apart, and it is then already available to the store.
///
/// `accent`, not `primaryColor`: accent is the selection / active-state
/// colour ("where you are") and affordability is a state — there is nothing
/// to tap per reward on this card. Same law as `ClassReservedTag`, whose
/// check glyph it borrows.
///
/// It is SOLID-filled rather than `ClassReservedTag`'s 10%-tint recipe
/// because it sits on an arbitrary gym photo: a translucent fill over a bright
/// upload would make the glyph and label unreadable. [RewardPriceTag] solves
/// the same problem the same way.
class RewardReadyTag extends StatelessWidget {
  const RewardReadyTag({super.key});

  @override
  Widget build(BuildContext context) {
    final onAccent = DesignConstants.accentButtonText;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingMedium,
        vertical: DesignConstants.spacingTiny,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.accent,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingSmall,
        children: [
          Icon(
            Symbols.check_sharp,
            weight: DesignConstants.iconWeight,
            size: DesignConstants.iconSizeXs,
            color: onAccent,
          ),
          Text(
            'Ready',
            style: DesignConstants.pSmall.copyWith(
              color: onAccent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
