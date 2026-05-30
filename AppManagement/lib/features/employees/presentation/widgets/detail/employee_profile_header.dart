import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/employees/data/mock_employees.dart';
import 'package:app_management/shared/widgets/app_outline_button.dart';
import 'package:app_management/shared/widgets/class_row/instructor_avatar.dart';

/// Top of the employee detail page: large headshot, name, role + status, and
/// email, followed by a row of staff actions. Left-aligned around the photo
/// (the member header centers a name with no photo; here the face leads).
class EmployeeProfileHeader extends StatelessWidget {
  final Employee employee;

  const EmployeeProfileHeader({super.key, required this.employee});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingBig,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingBig,
          children: [
            InstructorAvatar(
              photoUrl: employee.photoUrl,
              name: employee.fullName,
              diameter: 96,
            ),
            Expanded(child: _Identity(employee: employee)),
          ],
        ),
        const _ActionButtons(),
      ],
    );
  }
}

class _Identity extends StatelessWidget {
  final Employee employee;
  const _Identity({required this.employee});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(employee.fullName, style: DesignConstants.big2Bold),
        Text(
          employee.role.label,
          style: DesignConstants.h2.copyWith(color: DesignConstants.text2nd),
        ),
        _EmailLine(email: employee.email),
      ],
    );
  }
}

class _EmailLine extends StatelessWidget {
  final String email;
  const _EmailLine({required this.email});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(
          email,
          style: DesignConstants.h3.copyWith(color: DesignConstants.hyperlink),
        ),
        InkWell(
          onTap: () => debugPrint('TODO: copy email "$email"'),
          child: Icon(
            Symbols.content_copy_sharp,
            size: DesignConstants.iconSizeSmall,
            color: DesignConstants.text2nd,
            weight: DesignConstants.iconWeight,
          ),
        ),
      ],
    );
  }
}

class _ActionButtons extends StatelessWidget {
  const _ActionButtons();

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: DesignConstants.spacingLarge,
      children: [
        AppOutlineButton(
          text: 'Message',
          onPressed: () => debugPrint('TODO: message employee'),
        ),
        AppOutlineButton(
          text: 'Edit profile',
          onPressed: () => debugPrint('TODO: edit employee'),
        ),
        AppOutlineButton(
          text: 'Deactivate',
          onPressed: () => debugPrint('TODO: deactivate employee'),
        ),
      ],
    );
  }
}
