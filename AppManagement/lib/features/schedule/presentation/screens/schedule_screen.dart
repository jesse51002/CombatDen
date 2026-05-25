import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/core/navigation/app_routes.dart';
import 'package:app_management/features/schedule/data/mock_schedule.dart';
import 'package:app_management/features/schedule/presentation/widgets/header/schedule_header_bar.dart';
import 'package:app_management/features/schedule/presentation/widgets/list/schedule_class_list.dart';
import 'package:app_management/shared/widgets/app_shell.dart';

/// Gym Class Schedule screen.
///
/// Composition (top to bottom):
///   1. "Gym Class Schedule" subtitle
///   2. Header bar — month + chevrons, date-range pill, "Add New Class"
///   3. Stacked, day-grouped list of classes (image, instructor, points)
class ScheduleScreen extends StatelessWidget {
  const ScheduleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      activeRoute: AppRoutes.schedule,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DesignConstants.paddingBig),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingBig,
          children: [
            Text(
              'Gym Class Schedule',
              style: DesignConstants.h1.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
            const ScheduleHeaderBar(
              monthLabel: kScheduleMonthLabel,
              rangeLabel: kScheduleRangeLabel,
            ),
            ScheduleClassList(days: kMockScheduleDays),
          ],
        ),
      ),
    );
  }
}
