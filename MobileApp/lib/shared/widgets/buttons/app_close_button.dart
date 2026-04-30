import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_app/core/constants/design_constants.dart';

/// Generic close (X) button. Pops the nearest route by default; pass [onTap]
/// to override.
class AppCloseButton extends StatelessWidget {
  const AppCloseButton({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap ?? () => Navigator.of(context).maybePop(),
      child: Padding(
        padding: EdgeInsets.all(DesignConstants.spacingMedium),
        child: Icon(
          Symbols.close_sharp,
          weight: DesignConstants.iconWeight,
          color: DesignConstants.text,
          size: DesignConstants.iconSizeXl,
        ),
      ),
    );
  }
}
