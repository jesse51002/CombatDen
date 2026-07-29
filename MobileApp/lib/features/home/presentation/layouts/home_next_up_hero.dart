import 'package:flutter/material.dart';
import 'package:mobile_app/features/home/data/schedule_generator.dart';
import 'package:mobile_app/features/home/presentation/layouts/home_layout_data.dart';
import 'package:mobile_app/features/home/presentation/layouts/parts/home_header_metrics.dart';
import 'package:mobile_app/features/home/presentation/layouts/parts/home_schedule_scroll.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_item/class_item_layout.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/date_tab.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/day_class_group.dart';

const double _kDayGroupHeight = 560;

/// `HomeFormat.nextUpHero` — what is next, then everything else.
///
/// The upcoming-sessions card runs edge to edge as a hero, the date rail
/// becomes a segmented control that scrolls away with the content rather
/// than pinning, and the rest of the schedule collapses to dense rows.
/// The value that best serves the "before class, in a hurry" moment.
///
/// The docs' sketch also drops the class thumbnails and the gym mark
/// here. Both stay: removing an element is the one thing a format may
/// not do, and the gate in `test/home_invariants_test.dart` enforces it.
class HomeNextUpHero extends StatelessWidget {
  const HomeNextUpHero({super.key, required this.data});

  final HomeLayoutData data;

  @override
  Widget build(BuildContext context) {
    return HomeScheduleScroll(
      data: data,
      headerHeight: homeHeaderHeight(booked: data.booked),
      dayGroupHeight: _kDayGroupHeight,
      dateRowHeight: kHomeDateRowHeight,
      headerBleed: true,
      pinDateRow: false,
      dateTabStyle: DateTabStyle.segmented,
      scheduleSliver: (context) => SliverList.builder(
        itemBuilder: (context, index) => DayClassGroup(
          day: dayAt(index, data.loadedClasses),
          showBookings: data.booked,
          itemLayout: ClassItemLayout.dense,
        ),
      ),
    );
  }
}
