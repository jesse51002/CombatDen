import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/growth/presentation/widgets/growth_class_chips.dart';
import 'package:crm/features/growth/presentation/widgets/growth_class_filter.dart';
import 'package:crm/features/growth/presentation/widgets/growth_freshness_stamp.dart';
import 'package:crm/features/growth/presentation/widgets/growth_range.dart';
import 'package:crm/features/growth/presentation/widgets/growth_range_pill.dart';
import 'package:crm/shared/widgets/intrinsic_wrap.dart';

/// The row under the Growth tab bar: how fresh the numbers are, and the
/// filters that scope the tab below it.
///
/// ONE filter row above everything it scopes — never a per-chart filter,
/// which would leave the reader comparing two charts on different windows
/// without noticing.
class GrowthMetaRow extends StatelessWidget {
  final DateTime? computedAt;
  final GrowthRange range;

  /// Null hides the range pill (nothing on this tab to trim, or no page
  /// to filter yet).
  final ValueChanged<GrowthRange>? onRange;

  /// Empty hides the class chips (Attendance-only, and only when the
  /// tab's metrics actually carry `by_class`).
  final List<GrowthClassOption> classOptions;
  final String? selectedClassId;
  final ValueChanged<String?> onClass;

  const GrowthMetaRow({
    super.key,
    required this.computedAt,
    required this.range,
    required this.onRange,
    required this.classOptions,
    required this.selectedClassId,
    required this.onClass,
  });

  @override
  Widget build(BuildContext context) {
    final rangeChanged = onRange;
    // IntrinsicWrap so the stamp and the pills fall onto their own lines
    // below the breakpoint instead of overflowing.
    return IntrinsicWrap(
      spacing: DesignConstants.spacingLarge,
      runSpacing: DesignConstants.spacingMedium,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        GrowthFreshnessStamp(computedAt: computedAt),
        if (rangeChanged != null)
          GrowthRangePill(selected: range, onSelected: rangeChanged),
        if (classOptions.isNotEmpty)
          GrowthClassChips(
            options: classOptions,
            selectedClassId: selectedClassId,
            onSelected: onClass,
          ),
      ],
    );
  }
}
