import 'package:flutter/material.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/date_row.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/date_tab.dart';

/// Puts the [DateRow] in a sliver at a fixed height.
///
/// Whether it PINS is the format's call, set on the
/// `SliverPersistentHeader` that hosts this — the delegate itself is the
/// same either way.
class DateRowHeaderDelegate extends SliverPersistentHeaderDelegate {
  DateRowHeaderDelegate({
    required this.currentDayIndex,
    required this.scrollController,
    required this.height,
    required this.onDateTap,
    this.style = DateTabStyle.underline,
  });

  final int currentDayIndex;
  final ScrollController scrollController;
  final double height;
  final ValueChanged<int> onDateTap;
  final DateTabStyle style;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return DateRow(
      currentDayIndex: currentDayIndex,
      scrollController: scrollController,
      onDateTap: onDateTap,
      style: style,
    );
  }

  @override
  bool shouldRebuild(covariant DateRowHeaderDelegate oldDelegate) {
    return oldDelegate.currentDayIndex != currentDayIndex ||
        oldDelegate.height != height ||
        oldDelegate.style != style;
  }
}
