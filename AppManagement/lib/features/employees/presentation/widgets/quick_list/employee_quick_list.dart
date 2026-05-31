import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/core/navigation/app_routes.dart';
import 'package:app_management/features/employees/data/mock_employees.dart';
import 'package:app_management/features/employees/presentation/widgets/quick_list/employee_list_item.dart';
import 'package:app_management/shared/widgets/app_search_box.dart';

/// Right-side rail on the employee detail screen. Lets the admin jump between
/// employees without returning to the full list. Mirrors `MemberQuickList`,
/// but each row carries an avatar + role since this is a directory of people.
class EmployeeQuickList extends StatelessWidget {
  final List<Employee> employees;
  final String selectedId;

  const EmployeeQuickList({
    super.key,
    required this.employees,
    required this.selectedId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: DesignConstants.quickListWidth,
      padding: const EdgeInsets.all(DesignConstants.paddingBig),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingBig,
        children: [
          const AppSearchBox(hintText: 'search...'),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: DesignConstants.spacingMedium,
                children: [
                  for (final employee in employees)
                    EmployeeListItem(
                      employee: employee,
                      isSelected: employee.id == selectedId,
                      onTap: () => Navigator.pushReplacementNamed(
                        context,
                        '${AppRoutes.employeeDetail}?id=${employee.id}',
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
