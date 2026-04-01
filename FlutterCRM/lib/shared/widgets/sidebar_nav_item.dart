import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// A single navigation item in the left sidebar.
///
/// Displays an icon stacked above a label, with
/// active/inactive color states.
class SidebarNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback? onTap;

  const SidebarNavItem({
    super.key,
    required this.icon,
    required this.label,
    this.isActive = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive
        ? DesignConstants.primaryColor
        : DesignConstants.text3rd;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical:
              DesignConstants.spacingMedium,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(
              height:
                  DesignConstants.spacingTiny,
            ),
            Text(
              label,
              style: DesignConstants.pSmall.copyWith(
                color: color,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
