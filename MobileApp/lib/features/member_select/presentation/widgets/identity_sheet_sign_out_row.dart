import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:mobile_app/core/design_constants.dart';

/// The identity sheet's sign-out affordance: a plain row, deliberately the one
/// unfilled, uncarded item on the surface.
///
/// It is subordinate by ISOLATION and POSITION — below a divider, at the
/// extreme bottom, as far from the switch rows as the sheet allows — rather
/// than by alarm colour. Red belongs on the confirmation, not on the way in;
/// a red row here would read as an error state every time the sheet opens.
class IdentitySheetSignOutRow extends StatelessWidget {
  const IdentitySheetSignOutRow({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Sign out',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: DesignConstants.spacingLarge,
          ),
          child: Row(
            spacing: DesignConstants.spacingMedium,
            children: [
              Icon(
                Symbols.logout_sharp,
                weight: DesignConstants.iconWeight,
                color: DesignConstants.text2nd,
                size: DesignConstants.iconSizeSm,
              ),
              Text(
                'Sign out',
                style: DesignConstants.p.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
