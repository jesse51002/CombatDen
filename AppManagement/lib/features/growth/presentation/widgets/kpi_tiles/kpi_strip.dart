import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/growth/data/mock_growth.dart';
import 'package:app_management/features/growth/presentation/widgets/kpi_tiles/kpi_tile.dart';

/// Horizontal strip of four KPI tiles (Total / Trial / New / Lost).
class KpiStrip extends StatelessWidget {
  final List<GrowthKpi> kpis;

  const KpiStrip({super.key, required this.kpis});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingBig,
        children: [
          for (final kpi in kpis)
            Expanded(
              child: KpiTile(
                label: kpi.label,
                icon: kpiSymbolFor(kpi.icon),
                value: kpi.value,
                deltaLabel: kpi.deltaLabel,
                comparisonLabel: kpi.comparisonLabel,
              ),
            ),
        ],
      ),
    );
  }
}
