import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// A tappable "muted" adder tile: a plain divider-bordered row with a leading
/// glyph and a title + subtitle. The quiet counterpart to [DashedAddTile] (the
/// accent adder) — the shared idiom behind the members-step "authorize first"
/// affordance and the payer-step "Link someone" adder. One muted-tile layout,
/// not several.
class MutedAddTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const MutedAddTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.icon = Symbols.person_add_sharp,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(
        DesignConstants.radiusSmall,
      ),
      child: Container(
        padding: const EdgeInsets.all(
          DesignConstants.paddingSmall,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(
            DesignConstants.radiusSmall,
          ),
          border: Border.all(
            color: DesignConstants.divider,
          ),
        ),
        child: Row(
          spacing: DesignConstants.spacingMedium,
          children: [
            Icon(
              icon,
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
                    title,
                    style: DesignConstants.pSemibold,
                  ),
                  Text(
                    subtitle,
                    style: DesignConstants.pSmall.copyWith(
                      color: DesignConstants.text2nd,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
