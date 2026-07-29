import 'package:flutter/material.dart';
import 'package:mobile_app/features/home/data/schedule_generator.dart';
import 'package:mobile_app/features/home/presentation/layouts/home_layout_data.dart';
import 'package:mobile_app/features/home/presentation/layouts/parts/home_header_metrics.dart';
import 'package:mobile_app/features/home/presentation/layouts/parts/home_schedule_scroll.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/day_class_group.dart';

const double _kDayGroupHeight = 592;

/// `HomeFormat.agendaList` — the arrangement that ships today.
///
/// A pinned date rail over vertically stacked day groups, each class a
/// text-left / thumb-right row. Reproduces the previous home bodies
/// value for value, so a tenant with no layout slot sees no change.
class HomeAgendaList extends StatelessWidget {
  const HomeAgendaList({super.key, required this.data});

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
        ),
      ),
    );
  }
}
