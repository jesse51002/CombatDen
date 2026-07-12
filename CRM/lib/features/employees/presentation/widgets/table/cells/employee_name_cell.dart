import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/employees/data/models/employee.dart';
import 'package:crm/shared/widgets/class_row/instructor_avatar.dart';

/// "Name" column cell — the employee's headshot (or initials fallback)
/// alongside their full name. The face is the point of the Employees table,
/// so it leads the row.
class EmployeeNameCell extends StatelessWidget {
  final Employee employee;

  const EmployeeNameCell({super.key, required this.employee});

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        InstructorAvatar(
          photoUrl: employee.employeePicUrl,
          name: employee.fullName,
          diameter: 28,
        ),
        Flexible(
          child: Text(
            employee.fullName,
            style: DesignConstants.h3,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
