import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// A small chip shown on a membership card when that
/// membership's item is part of an in-progress upgrade task.
/// Mutation actions are disabled while this is visible.
class InTaskBadge extends StatelessWidget {
  const InTaskBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingMedium,
        vertical: DesignConstants.spacingSmall,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.accentSoft,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        border: Border.all(color: DesignConstants.primaryColor25),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingSmall,
        children: [
          Icon(
            Icons.sync,
            size: DesignConstants.iconSizeSmall,
            color: DesignConstants.primaryColor,
          ),
          Text(
            'Migrating…',
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.primaryColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
