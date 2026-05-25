import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/core/navigation/app_routes.dart';
import 'package:app_management/features/schedule/presentation/widgets/header/date_range_pill.dart';
import 'package:app_management/features/schedule/presentation/widgets/header/month_navigator.dart';
import 'package:app_management/shared/widgets/app_primary_button.dart';

/// Top action row of the Schedule screen.
///
/// Layout (left to right): month label + prev/next chevrons,
/// flexible spacer, date-range pill, "Add New Class" primary button.
class ScheduleHeaderBar extends StatelessWidget {
  final String monthLabel;
  final String rangeLabel;

  const ScheduleHeaderBar({
    super.key,
    required this.monthLabel,
    required this.rangeLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingLarge,
      children: [
        MonthNavigator(
          monthLabel: monthLabel,
          onPrevious: () =>
              debugPrint('TODO: change date range (previous)'),
          onNext: () => debugPrint('TODO: change date range (next)'),
        ),
        const Spacer(),
        DateRangePill(
          label: rangeLabel,
          onTap: () => debugPrint('TODO: change date range'),
        ),
        AppPrimaryButton(
          text: 'Add New Class',
          onPressed: () =>
              Navigator.pushNamed(context, AppRoutes.scheduleAddClass),
          textStyle: DesignConstants.h2,
          padding: const EdgeInsets.symmetric(
            horizontal: DesignConstants.paddingBig,
            vertical: DesignConstants.spacingMedium,
          ),
        ),
      ],
    );
  }
}
