import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// Title + live count subtitle for the Employees roster. Mirrors the Members
/// header so the two list surfaces read as siblings.
class EmployeesHeader extends StatelessWidget {
  final int total;

  const EmployeesHeader({super.key, required this.total});

  String get _subtitle =>
      total == 1 ? '1 team member' : '$total team members';

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
