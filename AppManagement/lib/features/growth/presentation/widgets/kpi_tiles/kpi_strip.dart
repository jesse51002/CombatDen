import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/growth/data/mock_growth.dart';
import 'package:app_management/features/growth/presentation/widgets/kpi_tiles/kpi_tile.dart';
import 'package:app_management/shared/widgets/hairline.dart';

/// Row of KPI stats (Total / New / Lost) separated by thin vertical
/// rules — no card chrome, the figures sit directly on the page.
class KpiStrip extends StatelessWidget {
  final List<GrowthKpi> kpis;

  const KpiStrip({super.key, required this.kpis});

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[];
    for (var i = 0; i < kpis.length; i++) {
      if (i > 0) {
        cells.add(const Hairline(vertical: true));
      }
      final kpi = kpis[i];
      cells.add(
        Expanded(
          child: KpiTile(
            label: kpi.label,
            icon: kpiSymbolFor(kpi.icon),
            value: kpi.value,
            deltaLabel: kpi.deltaLabel,
            comparisonLabel: kpi.comparisonLabel,
          ),
        ),
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingBig,
        children: cells,
      ),
    );
  }
}
