import 'package:flutter/material.dart';

import 'package:crm/features/growth/presentation/widgets/growth_range.dart';
import 'package:crm/shared/widgets/filter_pills.dart';

/// The Growth meta row's time-window control — All / Year / 6M / 3M.
///
/// One filter row above everything it scopes: the pill sits with the
/// freshness stamp above the tab body, never beside an individual chart.
class GrowthRangePill extends StatelessWidget {
  final GrowthRange selected;
  final ValueChanged<GrowthRange> onSelected;

  const GrowthRangePill({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return FilterPills(
      labels: [for (final r in GrowthRange.values) r.label],
      selectedIndex: GrowthRange.values.indexOf(selected),
      onSelected: (i) => onSelected(GrowthRange.values[i]),
    );
  }
}
