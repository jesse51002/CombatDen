import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// One pickable person, as a CONTAINED, unmistakably tappable row.
///
/// It is the kiosk's ONE "choose a person from a list" affordance: the home
/// check-in search, the payer picker's roster, and the payer/payee name search
/// all render their rows with it, so every "tap a member" surface looks and
/// behaves the same. A bordered, filled row with a press ripple and a trailing
/// chevron reads as a control at a glance — the same signal the search box
/// carries — rather than as a heading a member cannot tell apart from a section
/// label. That distinction is the whole point: a centred bold line looked
/// identical to the quiet titles above it, so nothing on the picker read as
/// pressable.
///
/// **Avatar-free, and that is deliberate**: a shared lobby iPad showing member
/// faces beside searchable names is a directory of everyone who trains here.
/// The FULL name is shown because two members sharing a first name and last
/// initial must stay distinguishable at the moment somebody taps one of them.
///
/// Rows carry no top hairline of their own — each is a self-contained control,
/// so the parent list spaces them with its own `spacing:` rather than a rule
/// between them.
class KioskNameRow extends StatelessWidget {
  final String name;

  /// The quiet second line — a masked email, or what they are on this roster
  /// for. Null renders the name alone.
  final String? note;

  final VoidCallback onTap;

  const KioskNameRow({
    super.key,
    required this.name,
    required this.onTap,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    final second = note;
    final radius = BorderRadius.circular(DesignConstants.radiusBig);
    return Material(
      color: DesignConstants.card,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: DesignConstants.line),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignConstants.spacingLarge,
              vertical: DesignConstants.spacingLarge,
            ),
            child: Row(
              spacing: DesignConstants.spacingMedium,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    spacing: DesignConstants.spacingTiny,
                    children: [
                      Text(
                        name,
                        style: DesignConstants.kioskName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (second != null)
                        Text(
                          second,
                          style: DesignConstants.kioskCaption.copyWith(
                            color: DesignConstants.text2nd,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                Icon(
                  Symbols.chevron_right_sharp,
                  size: DesignConstants.iconSizeMedium,
                  weight: DesignConstants.iconWeight,
                  color: DesignConstants.text2nd,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
