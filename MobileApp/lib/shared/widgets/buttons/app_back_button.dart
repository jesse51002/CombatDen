import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_app/core/design_constants.dart';

/// Generic back (chevron-left) button. Pops the nearest route by default;
/// pass [onTap] to override.
class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap ?? () => Navigator.of(context).maybePop(),
      child: Padding(
        padding: EdgeInsets.all(DesignConstants.spacingMedium),
        child: Icon(
          Symbols.chevron_left_sharp,
          weight: DesignConstants.iconWeight,
          color: DesignConstants.text,
          size: DesignConstants.iconSizeXl,
        ),
      ),
    );
  }
}
