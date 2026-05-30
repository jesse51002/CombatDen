import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/employees/data/mock_employees.dart';

/// "Role" column cell — the employee's role label, kept lighter than the
/// name so the eye lands on the person first, then their role.
class EmployeeRoleCell extends StatelessWidget {
  final EmployeeRole role;

  const EmployeeRoleCell({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    return Text(
      role.label,
      style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
