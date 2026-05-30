import 'package:flutter/material.dart';

import 'package:app_management/core/navigation/app_routes.dart';
import 'package:app_management/features/employees/data/mock_employees.dart';
import 'package:app_management/features/employees/presentation/widgets/table/cells/employee_classes_cell.dart';
import 'package:app_management/features/employees/presentation/widgets/table/cells/employee_name_cell.dart';
import 'package:app_management/features/employees/presentation/widgets/table/cells/employee_role_cell.dart';
import 'package:app_management/features/members/presentation/widgets/table/cells/member_contact_cell.dart';
import 'package:app_management/shared/widgets/app_data_table.dart';

/// Employees table — Name / Role / Contact / Classes / Status.
///
/// Wraps [AppDataTable] so the sticky-header / sized-column / row-tap
/// behaviour matches every other table in the app. Tapping a row opens that
/// employee's detail page (the id rides on the route so the right person
/// loads). [MemberContactCell] is reused for the email column — it's a
/// generic email-plus-copy cell, not member-specific.
class EmployeesTable extends StatelessWidget {
  final List<Employee> employees;

  const EmployeesTable({super.key, required this.employees});

  @override
  Widget build(BuildContext context) {
    return AppDataTable(
      shrinkWrap: true,
      columns: const [
        AppDataTableColumn(label: 'Name', minWidth: 220, fill: true),
        AppDataTableColumn(label: 'Role', minWidth: 130, fill: true),
        AppDataTableColumn(label: 'Contact', minWidth: 220, fill: true),
        AppDataTableColumn(label: 'Classes', minWidth: 110),
      ],
      rows: employees.map((e) {
        return AppDataTableRow(
          onTap: () => Navigator.pushNamed(
            context,
            '${AppRoutes.employeeDetail}?id=${e.id}',
          ),
          cells: [
            EmployeeNameCell(employee: e),
            EmployeeRoleCell(role: e.role),
            MemberContactCell(email: e.email),
            EmployeeClassesCell(classesPerWeek: e.classesPerWeek),
          ],
        );
      }).toList(),
    );
  }
}
