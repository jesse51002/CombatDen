import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/schedule/data/mock_schedule.dart';
import 'package:app_management/features/schedule/presentation/widgets/calendar/schedule_class_block.dart';

/// Width of the leading time-of-day column (the labels on the left).
const double _kTimeColumnWidth = 64;

/// Height of one hour row. Sized to comfortably fit the class block
/// (name + time line + padding) without overflow on web.
const double _kRowHeight = 88;

/// Custom 7-day x N-hour calendar grid.
///
/// Built on Flutter's `Table` widget so every row uses the EXACT same
/// column boundaries — alignment between the day-of-week header row and
/// the hour rows is guaranteed by construction (no flex-distribution
/// drift caused by per-cell intrinsic widths). The first column is a
/// fixed-width time-of-day column; the remaining 7 columns share the
/// remaining width equally.
class ScheduleCalendar extends StatelessWidget {
  final ScheduleWeek week;

  const ScheduleCalendar({super.key, required this.week});

  @override
  Widget build(BuildContext context) {
    return Table(
      columnWidths: const {
        0: FixedColumnWidth(_kTimeColumnWidth),
        1: FlexColumnWidth(),
        2: FlexColumnWidth(),
        3: FlexColumnWidth(),
        4: FlexColumnWidth(),
        5: FlexColumnWidth(),
        6: FlexColumnWidth(),
        7: FlexColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        _headerRow(week.days),
        for (int i = 0; i < kScheduleHourRowCount; i++)
          _hourRow(
            hour: kScheduleStartHour + i,
            classes: week.classes,
          ),
      ],
    );
  }

  TableRow _headerRow(List<ScheduleDay> days) {
    return TableRow(
      children: [
        const SizedBox.shrink(),
        for (final day in days)
          Padding(
            padding: const EdgeInsets.only(
              bottom: DesignConstants.spacingLarge,
            ),
            child: _DayHeaderCell(day: day),
          ),
      ],
    );
  }

  TableRow _hourRow({
    required int hour,
    required List<ScheduleClassBlock> classes,
  }) {
    return TableRow(
      children: [
        SizedBox(
          height: _kRowHeight,
          child: _TimeLabel(hour: hour),
        ),
        for (int day = 0; day < 7; day++)
          _DayCell(
            height: _kRowHeight,
            block: _findBlock(classes, day, hour),
          ),
      ],
    );
  }

  ScheduleClassBlock? _findBlock(
    List<ScheduleClassBlock> classes,
    int day,
    int hour,
  ) {
    for (final c in classes) {
      if (c.dayIndex == day && c.startHour == hour) return c;
    }
    return null;
  }
}

class _DayHeaderCell extends StatelessWidget {
  final ScheduleDay day;
  const _DayHeaderCell({required this.day});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingSmall,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingSmall,
        children: [
          Text(day.label, style: DesignConstants.h2Regular),
          Text(
            '${day.dayOfMonth}',
            style: DesignConstants.h1Regular.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeLabel extends StatelessWidget {
  final int hour;
  const _TimeLabel({required this.hour});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(
          top: DesignConstants.spacingSmall,
        ),
        child: Text(
          _format(hour),
          style: DesignConstants.h3.copyWith(
            color: DesignConstants.text3rd,
          ),
        ),
      ),
    );
  }

  String _format(int h) {
    if (h == 0) return '12 am';
    if (h == 12) return '12 pm';
    return h < 12 ? '$h am' : '${h - 12} pm';
  }
}

/// Single (day, hour) cell. Renders the class tile pinned to the top of
/// the hour row if a class starts here, otherwise an empty bordered
/// cell. The top edge gets a 1px gridline so rows visually separate.
class _DayCell extends StatelessWidget {
  final double height;
  final ScheduleClassBlock? block;

  const _DayCell({required this.height, required this.block});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: DesignConstants.divider,
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingSmall,
        vertical: DesignConstants.spacingSmall,
      ),
      child: block == null
          ? const SizedBox.shrink()
          : SizedBox.expand(
              child: ScheduleClassBlockTile(block: block!),
            ),
    );
  }
}
