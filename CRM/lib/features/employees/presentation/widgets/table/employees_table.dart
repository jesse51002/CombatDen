import 'package:flutter/material.dart';

import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/features/employees/data/models/employee.dart';
import 'package:crm/features/employees/data/models/employee_taught_class.dart';
import 'package:crm/features/employees/presentation/widgets/table/cells/employee_classes_cell.dart';
import 'package:crm/features/employees/presentation/widgets/table/cells/employee_invite_cell.dart';
import 'package:crm/features/employees/presentation/widgets/table/cells/employee_name_cell.dart';
import 'package:crm/features/employees/presentation/widgets/table/cells/employee_role_cell.dart';
import 'package:crm/features/members/presentation/widgets/table/cells/member_contact_cell.dart';
import 'package:crm/shared/widgets/app_data_table.dart';

/// Employees table — Name / Role / Contact / Classes / Status.
///
/// Wraps [AppDataTable] so the sticky-header / sized-column / row-tap behaviour
/// matches every other table in the app. Tapping a row deep-links to that
/// employee's detail page. [MemberContactCell] is reused for the email column
/// (a generic email cell). The Classes cell shows the weekly-session count
/// derived from [taughtByEmployeeId] — an em dash when the employee teaches
/// nothing or the classes side-load failed. The Status cell carries the
/// resend-invite affordance for a row still `pending` ([EmployeeInviteCell]).
class EmployeesTable extends StatelessWidget {
  final List<Employee> employees;
  final Map<String, List<EmployeeTaughtClass>> taughtByEmployeeId;
  final bool classesLoadFailed;

  /// The row whose invite resend is in flight, if any.
  final String? resendingEmployeeId;

  const EmployeesTable({
    super.key,
    required this.employees,
    required this.taughtByEmployeeId,
    required this.classesLoadFailed,
    this.resendingEmployeeId,
  });

  int? _classCount(Employee e) {
    if (classesLoadFailed) return null;
    final taught = taughtByEmployeeId[e.employeeId];
    if (taught == null) return null;
    return taught.fold<int>(0, (sum, t) => sum + t.slotLabels.length);
  }

  @override
  Widget build(BuildContext context) {
    return AppDataTable(
      shrinkWrap: true,
      columns: const [
        AppDataTableColumn(label: 'Name', minWidth: 220, fill: true),
        AppDataTableColumn(label: 'Role', minWidth: 130, fill: true),
        AppDataTableColumn(label: 'Contact', minWidth: 220, fill: true),
        AppDataTableColumn(label: 'Classes', minWidth: 110),
        // Wider than the other status columns: this one also carries the
        // "Resend invite" affordance for a pending row.
        AppDataTableColumn(label: 'Status', minWidth: 240),
      ],
      rows: employees.map((e) {
        return AppDataTableRow(
          onTap: () => Navigator.pushNamed(
            context,
            AppRoutes.employeeDetailPath(e.employeeId),
          ),
          cells: [
            EmployeeNameCell(employee: e),
            EmployeeRoleCell(role: e.employeeType),
            MemberContactCell(email: e.email),
            EmployeeClassesCell(classesPerWeek: _classCount(e)),
            EmployeeInviteCell(
              employee: e,
              resending: resendingEmployeeId == e.employeeId,
              anyResending: resendingEmployeeId != null,
            ),
          ],
        );
      }).toList(),
    );
  }
}
