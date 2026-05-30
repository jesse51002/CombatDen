import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/employees/data/mock_employees.dart';
import 'package:app_management/shared/widgets/class_row/instructor_avatar.dart';

/// One employee row in the detail page's right-rail quick-list: avatar, name,
/// and role. The currently-open employee's name is drawn in the sapphire
/// accent — selection is exactly what that one accent is for.
class EmployeeListItem extends StatelessWidget {
  final Employee employee;
  final bool isSelected;
  final VoidCallback? onTap;

  const EmployeeListItem({
    super.key,
    required this.employee,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final nameColor =
        isSelected ? DesignConstants.primaryColor : DesignConstants.text;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: DesignConstants.spacingMedium,
        ),
        child: Row(
          spacing: DesignConstants.spacingMedium,
          children: [
            InstructorAvatar(
              photoUrl: employee.photoUrl,
              name: employee.fullName,
              diameter: 32,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: DesignConstants.spacingTiny,
                children: [
                  Text(
                    employee.fullName,
                    style: DesignConstants.h3.copyWith(color: nameColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    employee.role.label,
                    style: DesignConstants.p.copyWith(
                      color: DesignConstants.text2nd,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
