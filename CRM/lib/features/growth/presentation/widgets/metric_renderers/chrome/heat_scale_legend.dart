import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/painters/heat_density.dart';

/// The density scale key for an unlabelled heat grid: `Quiet` — four
/// swatches — `Busy`.
///
/// The grid's cells carry no numbers, so this is what makes the ramp
/// readable at all.
class HeatScaleLegend extends StatelessWidget {
  const HeatScaleLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final style = DesignConstants.pSmall.copyWith(
      color: DesignConstants.text3rd,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text('Quiet', style: style),
        for (final swatch in heatLegendSwatches())
          Container(
            width: DesignConstants.spacingMedium +
                DesignConstants.spacingSmall,
            height: DesignConstants.spacingMedium +
                DesignConstants.spacingSmall,
            decoration: BoxDecoration(
              color: swatch,
              border: Border.all(color: DesignConstants.line),
            ),
          ),
        Text('Busy', style: style),
      ],
    );
  }
}
