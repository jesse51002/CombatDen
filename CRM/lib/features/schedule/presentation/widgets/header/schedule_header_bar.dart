import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/schedule/presentation/widgets/header/month_navigator.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';

/// Top action row of the Schedule screen.
///
/// Layout (left to right): the visible week's date range + prev/next chevrons
/// (which move the board a week at a time), a flexible spacer, and — when the
/// caller may edit the schedule ([showAddClass]) — the "Add New Class" button.
/// Front desk + trainer (read-only schedule) don't see the button.
class ScheduleHeaderBar extends StatelessWidget {
  final String rangeLabel;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  /// Opens the create-class form (provided with the board's [ScheduleBloc]).
  final VoidCallback onAddClass;

  /// Whether the "Add New Class" button renders (owner/admin only). Creating a
  /// class is a schedule-definition edit, so front desk + trainer never see it.
  final bool showAddClass;

  const ScheduleHeaderBar({
    super.key,
    required this.rangeLabel,
    required this.onPrevious,
    required this.onNext,
    required this.onAddClass,
    required this.showAddClass,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingLarge,
      children: [
        MonthNavigator(
          label: rangeLabel,
          onPrevious: onPrevious,
          onNext: onNext,
        ),
        const Spacer(),
        if (showAddClass)
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
