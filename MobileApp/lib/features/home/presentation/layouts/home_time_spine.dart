import 'package:flutter/material.dart';
import 'package:mobile_app/features/home/data/schedule_generator.dart';
import 'package:mobile_app/features/home/presentation/layouts/home_layout_data.dart';
import 'package:mobile_app/features/home/presentation/layouts/parts/home_header_metrics.dart';
import 'package:mobile_app/features/home/presentation/layouts/parts/home_schedule_scroll.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_item/class_item_layout.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/day_class_group.dart';

const double _kDayGroupHeight = 490;

/// `HomeFormat.timeSpine` — the day reads as a timetable.
///
/// The time leaves the meta column and becomes a left gutter, with a
/// vertical rule running down every row so consecutive classes read as
/// one continuous spine; the thumbnail demotes to a small square. What a
/// member with three classes in one evening actually needs.
class HomeTimeSpine extends StatelessWidget {
  const HomeTimeSpine({super.key, required this.data});

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
          itemLayout: ClassItemLayout.spine,
        ),
      ),
    );
  }
}
