import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/employees/data/models/employee.dart';
import 'package:crm/features/employees/data/models/employees_format.dart';
import 'package:crm/shared/widgets/info_row.dart';

/// The contact + tenure record as label: value rows — email (or "No login" for
/// an email-less instructor), phone when present, and when they joined (derived
/// from `created_at`).
class EmployeeInfoSection extends StatelessWidget {
  final Employee employee;

  const EmployeeInfoSection({super.key, required this.employee});

  @override
  Widget build(BuildContext context) {
    final email = employee.email;
    final phone = employee.phone;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        if (email != null && email.isNotEmpty)
          InfoRow(
            label: 'Email',
            value: email,
            linkType: InfoRowLinkType.email,
          )
        else
          const InfoRow(label: 'Email', value: 'No login on file'),
        if (phone != null && phone.isNotEmpty)
          InfoRow(
            label: 'Phone',
            value: phone,
            linkType: InfoRowLinkType.phone,
          ),
        InfoRow(label: 'Joined', value: joinedLabel(employee.createdAt)),
      ],
    );
  }
}
