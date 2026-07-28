import 'package:flutter/material.dart';
import 'package:mobile_app/features/home/presentation/layouts/home_layout_data.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/schedule_status.dart';

/// What stands in for the day list while it is loading, failed, or
/// genuinely empty.
///
/// Only built when [HomeLayoutData.hasSchedule] is false — a loaded,
/// non-empty schedule shows no status at all, which is the shipped
/// behaviour.
class HomeStatus extends StatelessWidget {
  const HomeStatus({super.key, required this.data});

  final HomeLayoutData data;

  @override
  Widget build(BuildContext context) {
    return switch (data.state) {
      HomeScheduleState.error => const ScheduleStatus(
        message: "Couldn't load classes right now.",
      ),
      HomeScheduleState.loading => const ScheduleStatus(loading: true),
      HomeScheduleState.empty => const ScheduleStatus(
        message: 'No classes scheduled.',
      ),
      HomeScheduleState.loaded => const ScheduleStatus(),
    };
  }
}
