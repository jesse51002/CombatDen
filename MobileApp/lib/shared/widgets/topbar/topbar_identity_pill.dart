import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_app/core/design_constants.dart';

/// The topbar's **identity line** — the second line under the gym name: the
/// selected member's name in a filled pill with the switch chevron.
///
/// One verified email legitimately resolves to several member rows (a family
/// shares an inbox, possibly across gyms), so the topbar has to answer "who am
/// I right now?" as well as "which gym?". The gym stays the visually primary
/// brand anchor; the person is the secondary, switchable line — which is why
/// the chevron sits here, on the thing the tap actually changes.
class TopbarIdentityPill extends StatelessWidget {
  const TopbarIdentityPill({super.key, required this.memberName});

  final String memberName;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusCircle),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingMedium,
        vertical: DesignConstants.spacingSmall,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingSmall,
        children: [
          Flexible(
            child: Text(
              memberName,
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.text2nd,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(
            Symbols.expand_more_sharp,
            weight: DesignConstants.iconWeight,
            color: DesignConstants.text2nd,
            size: DesignConstants.iconSizeXs,
          ),
        ],
      ),
    );
  }
}
