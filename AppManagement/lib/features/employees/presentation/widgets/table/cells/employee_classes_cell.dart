import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/employees/presentation/widgets/table/_helpers.dart';

/// "Classes" column cell — classes-per-week for coaches, an em dash for staff
/// who don't teach. Tabular figures (from the base font) keep the column
/// aligned down the table.
class EmployeeClassesCell extends StatelessWidget {
  final int? classesPerWeek;

  const EmployeeClassesCell({super.key, required this.classesPerWeek});

  @override
  Widget build(BuildContext context) {
    final hasClasses = classesPerWeek != null;
    return Text(
      classesPerWeekLabel(classesPerWeek),
      style: DesignConstants.h3.copyWith(
        color: hasClasses ? DesignConstants.text : DesignConstants.text3rd,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
