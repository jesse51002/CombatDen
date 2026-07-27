import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_app/core/design_constants.dart';

/// Leading back chevron. Shared by every shell layout so the control is
/// defined once and only its placement varies.
class TopbarBackButton extends StatelessWidget {
  const TopbarBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).maybePop(),
      child: Padding(
        padding: EdgeInsets.all(DesignConstants.spacingMedium),
        child: Icon(
          Symbols.chevron_left_sharp,
          weight: DesignConstants.iconWeight,
          color: DesignConstants.text,
          size: DesignConstants.iconSize2xl,
        ),
      ),
    );
  }
}
