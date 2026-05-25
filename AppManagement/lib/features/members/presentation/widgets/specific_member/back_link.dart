import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:app_management/core/constants/design_constants.dart';

/// "< Back" link rendered in the top-left of the member profile card.
///
/// Pops the current route. If there is no route to pop, falls back
/// to the Members list (for example when the screen is opened
/// directly via deep link).
class BackLink extends StatelessWidget {
  final VoidCallback onTap;

  const BackLink({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = DesignConstants.text3rd;

    return InkWell(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingSmall,
        children: [
          Icon(
            Symbols.chevron_left_sharp,
            size: DesignConstants.iconSizeMedium,
            color: color,
            weight: DesignConstants.iconWeight,
          ),
          Text(
            'Back',
            style: DesignConstants.h3.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
