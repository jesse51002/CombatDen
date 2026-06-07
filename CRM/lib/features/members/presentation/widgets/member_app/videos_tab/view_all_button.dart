import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The "View all ›" link that sits at the end of a feed section header and
/// jumps the feed to that section's full grid. Shared by the genre rows and
/// the "Your videos" row so every section opens the same View all view.
class ViewAllButton extends StatelessWidget {
  final VoidCallback onTap;

  const ViewAllButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingTiny,
        children: [
          Text(
            'View all',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.primaryColor,
            ),
          ),
          Icon(
            Symbols.chevron_right_sharp,
            color: DesignConstants.primaryColor,
            weight: DesignConstants.iconWeight,
            size: DesignConstants.iconSizeSmall,
          ),
        ],
      ),
    );
  }
}
