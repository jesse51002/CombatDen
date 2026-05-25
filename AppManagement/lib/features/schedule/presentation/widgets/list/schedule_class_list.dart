import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/schedule/data/mock_schedule.dart';
import 'package:app_management/features/schedule/presentation/widgets/list/schedule_day_column.dart';

/// Minimum width a day column needs before a day is dropped. Tuned so a full
/// 7-day week fits on a desktop content area and the count steps down on
/// narrower screens.
const double _kMinDayColumnWidth = 150;

/// The schedule as a board of day columns laid out side by side and split by
/// vertical dividers, each column holding that day's classes stacked. The
/// number of visible days shrinks responsively as the screen narrows.
class ScheduleClassList extends StatelessWidget {
  final List<ScheduleDayGroup> days;

  const ScheduleClassList({super.key, required this.days});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fit = (constraints.maxWidth / _kMinDayColumnWidth).floor();
        final count = fit.clamp(1, days.length);
        final shown = _windowedDays(count);

        final children = <Widget>[];
        for (var i = 0; i < shown.length; i++) {
          children.add(Expanded(child: ScheduleDayColumn(group: shown[i])));
          if (i < shown.length - 1) children.add(const _ColumnDivider());
        }

        // IntrinsicHeight bounds the row to the tallest column so the
        // stretched column dividers can span the full height inside the
        // (vertically unbounded) page scroll view.
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DesignConstants.spacingLarge,
            children: children,
          ),
        );
      },
    );
  }

  /// When not every day fits, keep the current day (and the days after it)
  /// visible instead of always starting at Sunday.
  List<ScheduleDayGroup> _windowedDays(int count) {
    if (count >= days.length) return days;
    final todayIndex = days.indexWhere((d) => d.isToday);
    final anchor = todayIndex < 0 ? 0 : todayIndex;
    final start = anchor.clamp(0, days.length - count);
    return days.sublist(start, start + count);
  }
}

class _ColumnDivider extends StatelessWidget {
  const _ColumnDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, color: DesignConstants.divider);
  }
}
