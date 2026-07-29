import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_app/core/design_constants.dart';

/// The gym name plus its switch-gym chevron.
///
/// [visuallyHidden] keeps the label in the tree for screen readers and
/// as the switch-gym tap target while removing it from the visual
/// layout. That is what lets `AppShellFormat.markOnly` drop the name
/// from the screen without dropping the affordance.
class GymNameLabel extends StatelessWidget {
  const GymNameLabel({
    super.key,
    required this.gymName,
    this.style,
    this.visuallyHidden = false,
  });

  final String gymName;
  final TextStyle? style;
  final bool visuallyHidden;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingSmall,
      children: [
        Flexible(
          child: Text(
            gymName,
            style: style ?? DesignConstants.h2,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Icon(
          Symbols.expand_more_sharp,
          weight: DesignConstants.iconWeight,
          color: DesignConstants.text,
          size: DesignConstants.iconSizeSm,
        ),
      ],
    );
    if (!visuallyHidden) return row;
    // Still rendered and still hit-testable, just not laid out.
    return Semantics(
      label: gymName,
      child: SizedBox.shrink(child: OverflowBox(maxWidth: 0, child: row)),
    );
  }
}
