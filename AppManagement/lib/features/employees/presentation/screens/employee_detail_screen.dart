import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/core/navigation/app_routes.dart';
import 'package:app_management/features/employees/data/mock_employees.dart';
import 'package:app_management/features/employees/presentation/widgets/detail/employee_profile.dart';
import 'package:app_management/features/employees/presentation/widgets/quick_list/employee_quick_list.dart';
import 'package:app_management/shared/widgets/app_shell.dart';
import 'package:app_management/shared/widgets/hairline.dart';

/// Employee detail screen — its own page, reached by tapping a row in the
/// Employees table.
///
/// Composition (left to right), matching the member detail screen:
///   1. SectionsBar (via AppShell, active item = Employees)
///   2. The employee profile (de-carded sections, hairline-separated)
///   3. A right rail to jump between employees without going back
///
/// The id rides on the route as `?id=…`; we resolve it off the route name so
/// tapping different rows opens different people. Falls back to the first
/// employee for a bare `/employees/detail` (e.g. a deep link).
class EmployeeDetailScreen extends StatelessWidget {
  const EmployeeDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final employee = _resolveEmployee(context);

    return AppShell(
      activeRoute: AppRoutes.employees,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(DesignConstants.paddingBig),
              child: EmployeeProfile(employee: employee),
            ),
          ),
          const Hairline(vertical: true),
          EmployeeQuickList(
            employees: kMockEmployees,
            selectedId: employee.id,
          ),
        ],
      ),
    );
  }

  Employee _resolveEmployee(BuildContext context) {
    final routeName = ModalRoute.of(context)?.settings.name;
    final id = routeName == null
        ? null
        : Uri.parse(routeName).queryParameters['id'];
    return kMockEmployees.firstWhere(
      (e) => e.id == id,
      orElse: () => kMockEmployees.first,
    );
  }
}
