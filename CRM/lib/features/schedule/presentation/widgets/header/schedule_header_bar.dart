import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/schedule/presentation/widgets/header/date_range_pill.dart';
import 'package:crm/features/schedule/presentation/widgets/header/month_navigator.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';

/// Top action row of the Schedule screen.
///
/// Layout (left to right): month label + prev/next chevrons (which move the
/// board a week at a time), flexible spacer, the visible-week range pill, and
/// the "Add New Class" button.
class ScheduleHeaderBar extends StatelessWidget {
  final String monthLabel;
  final String rangeLabel;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  /// Opens the create-class form (provided with the board's [ScheduleBloc]).
  final VoidCallback onAddClass;

  const ScheduleHeaderBar({
    super.key,
    required this.monthLabel,
    required this.rangeLabel,
    required this.onPrevious,
    required this.onNext,
    required this.onAddClass,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingLarge,
      children: [
        MonthNavigator(
          monthLabel: monthLabel,
          onPrevious: onPrevious,
          onNext: onNext,
        ),
        const Spacer(),
        DateRangePill(label: rangeLabel),
        AppPrimaryButton(
          text: 'Add New Class',
          onPressed: onAddClass,
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
