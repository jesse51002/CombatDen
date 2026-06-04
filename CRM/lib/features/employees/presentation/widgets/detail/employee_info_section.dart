import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/employees/data/mock_employees.dart';
import 'package:crm/shared/widgets/info_row.dart';

/// The contact + employment record as label: value rows: email, phone, when
/// they joined, tenure, and employment type.
class EmployeeInfoSection extends StatelessWidget {
  final Employee employee;

  const EmployeeInfoSection({super.key, required this.employee});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        InfoRow(
          label: 'Email',
          value: employee.email,
          linkType: InfoRowLinkType.email,
        ),
        InfoRow(
          label: 'Phone',
          value: employee.phone,
          linkType: InfoRowLinkType.phone,
        ),
        InfoRow(label: 'Joined', value: employee.joinedLabel),
        InfoRow(label: 'Tenure', value: employee.tenureLabel),
        InfoRow(label: 'Employment', value: employee.employmentLabel),
      ],
    );
  }
}
