import 'package:flutter/material.dart';
import 'package:mobile_app/features/home/data/schedule_generator.dart';
import 'package:mobile_app/features/home/presentation/layouts/home_layout_data.dart';
import 'package:mobile_app/features/home/presentation/layouts/parts/home_header_metrics.dart';
import 'package:mobile_app/features/home/presentation/layouts/parts/home_schedule_scroll.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/day_class_group.dart';

const double _kDayGroupHeight = 580;

/// `HomeFormat.boardGrid` — the densest read per scroll.
///
/// Each day is a band header over a two-up card grid. Buys the most
/// classes per screen and pays for it in time hierarchy: two classes
/// side by side no longer read as "this one, then that one".
class HomeBoardGrid extends StatelessWidget {
  const HomeBoardGrid({super.key, required this.data});

  final HomeLayoutData data;

  @override
  Widget build(BuildContext context) {
    return HomeScheduleScroll(
      data: data,
      headerHeight: homeHeaderHeight(booked: data.booked),
      dayGroupHeight: _kDayGroupHeight,
      dateRowHeight: kHomeDateRowHeight,
      scheduleSliver: (context) => SliverList.builder(
        itemBuilder: (context, index) => DayClassGroup(
          day: dayAt(index, data.loadedClasses),
          showBookings: data.booked,
          grid: true,
        ),
      ),
    );
  }
}
