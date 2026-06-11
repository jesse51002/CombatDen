import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// "Someone missing?" — unlinked members can't receive a
/// membership in this run; staff link them first via the
/// existing link flow, then return here.
class StartLinkFirstTile extends StatelessWidget {
  final VoidCallback onTap;

  const StartLinkFirstTile({
    super.key,
    required this.onTap,
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
              Symbols.person_add_sharp,
              weight: DesignConstants.iconWeight,
              size: DesignConstants.iconSizeMedium,
              color: DesignConstants.text2nd,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                spacing: DesignConstants.spacingTiny,
                children: [
                  Text(
                    'Someone missing? Link them first',
                    style: DesignConstants.pSemibold,
                  ),
                  Text(
                    'Unlinked members can’t be enrolled '
                    'here — starting never links.',
                    style: DesignConstants.pSmall
                        .copyWith(
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
