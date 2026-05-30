import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/employees/data/mock_employees.dart';

/// Title + summary subtitle for the Employees screen. Mirrors `MembersHeader`
/// so the two list screens read as siblings.
class EmployeesHeader extends StatelessWidget {
  final EmployeesSummary summary;

  const EmployeesHeader({super.key, required this.summary});

  String get _subtitle =>
      '${summary.total} team members · ${summary.coaches} coaches';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text('Employees', style: DesignConstants.big2),
        Text(
          _subtitle,
          style: DesignConstants.h1Regular.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
      ],
    );
  }
}
