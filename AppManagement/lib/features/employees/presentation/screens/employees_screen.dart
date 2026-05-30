import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/core/navigation/app_routes.dart';
import 'package:app_management/features/employees/data/mock_employees.dart';
import 'package:app_management/features/employees/presentation/widgets/controls/employees_controls.dart';
import 'package:app_management/features/employees/presentation/widgets/header/employees_header.dart';
import 'package:app_management/features/employees/presentation/widgets/table/employees_table.dart';
import 'package:app_management/shared/widgets/app_shell.dart';

/// Gym admin Employees list screen.
///
/// Composition (top to bottom), matching the Members screen so the two read
/// as siblings:
///   1. "Employees" title + team summary subtitle.
///   2. Search box + "Add Employee" primary button + "Add Filter" pill.
///   3. Tappable table — Name / Role / Contact / Classes / Status. A row
///      opens that employee's detail page.
class EmployeesScreen extends StatelessWidget {
  const EmployeesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final summary = buildEmployeesSummary(kMockEmployees);

    return AppShell(
      activeRoute: AppRoutes.employees,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          vertical: DesignConstants.paddingBig,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingBig,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignConstants.paddingBig,
              ),
              child: EmployeesHeader(summary: summary),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: DesignConstants.paddingBig,
              ),
              child: EmployeesControls(),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignConstants.paddingSmall,
              ),
              child: EmployeesTable(employees: kMockEmployees),
            ),
          ],
        ),
      ),
    );
  }
}
