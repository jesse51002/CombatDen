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
  final bool isPrimary;

  const SidebarNavItem({
    super.key,
    required this.icon,
    required this.label,
    this.isActive = false,
    this.onTap,
    this.isPrimary = false
  });

  @override
  Widget build(BuildContext context) {

    Color textColor = isActive ?
      DesignConstants.text : DesignConstants.text2nd;

    textColor = isPrimary ?
      DesignConstants.primaryColor : textColor;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical:
              DesignConstants.spacingMedium,
        ),
        child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: DesignConstants.spacingTiny,
              children: [
                Icon(icon, color: textColor, size: 24, weight: DesignConstants.iconWeight,),
                Text(
                  label,
                  style: DesignConstants.h3.copyWith(
                    color: textColor,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
          ),
        ) 
        
      ),
    );
  }
}
