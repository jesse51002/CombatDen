import 'package:flutter/material.dart';

import 'package:crm/features/growth/presentation/widgets/growth_class_filter.dart';
import 'package:crm/shared/widgets/filter_pills.dart';

/// The Attendance tab's class filter — "All classes" plus one chip per
/// class the tab's metrics carry a `by_class` slice for.
///
/// Selecting a class swaps every section that carries that class onto its
/// slice; a section without one renders unchanged. Index 0 is the
/// all-classes view, so [selectedClassId] is null there.
class GrowthClassChips extends StatelessWidget {
  final List<GrowthClassOption> options;
  final String? selectedClassId;
  final ValueChanged<String?> onSelected;

  const GrowthClassChips({
    super.key,
    required this.options,
    required this.selectedClassId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    var index = 0;
    for (var i = 0; i < options.length; i++) {
      if (options[i].classId == selectedClassId) {
        index = i + 1;
        break;
      }
    }
    return FilterPills(
      labels: ['All classes', for (final o in options) o.className],
      selectedIndex: index,
      onSelected: (i) => onSelected(i == 0 ? null : options[i - 1].classId),
    );
  }
}
