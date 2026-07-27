import 'package:flutter/material.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/date_row.dart';

class PinnedDateRowDelegate extends SliverPersistentHeaderDelegate {
  PinnedDateRowDelegate({
    required this.currentDayIndex,
    required this.scrollController,
    required this.height,
    required this.onDateTap,
  });

  final int currentDayIndex;
  final ScrollController scrollController;
  final double height;
  final ValueChanged<int> onDateTap;

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
    );
  }

  @override
  bool shouldRebuild(covariant PinnedDateRowDelegate oldDelegate) {
    return oldDelegate.currentDayIndex != currentDayIndex ||
        oldDelegate.height != height;
  }
}
