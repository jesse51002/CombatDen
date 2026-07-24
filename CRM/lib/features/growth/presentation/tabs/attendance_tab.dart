import 'package:flutter/material.dart';

import 'package:crm/features/growth/bloc/growth_state.dart';
import 'package:crm/features/growth/data/models/growth_metric.dart';
import 'package:crm/features/growth/presentation/widgets/growth_range.dart';
import 'package:crm/features/growth/presentation/widgets/growth_tab_body.dart';

/// The Growth page's Attendance tab — the one tab with a class filter.
///
/// The selected class is chosen in the page's meta row and handed down;
/// sections carrying a `by_class` slice swap onto it, the rest render
/// unchanged.
class AttendanceTab extends StatelessWidget {
  final GrowthState state;
  final GrowthRange range;
  final String? classId;
  final String? className;
  final bool compact;

  const AttendanceTab({
    super.key,
    required this.state,
    required this.range,
    this.classId,
    this.className,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return GrowthTabBody(
      state: state,
      category: GrowthCategory.attendance,
      range: range,
      classId: classId,
      className: className,
      compact: compact,
    );
  }
}
