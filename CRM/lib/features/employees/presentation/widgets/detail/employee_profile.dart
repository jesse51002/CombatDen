import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/features/employees/data/models/employee.dart';
import 'package:crm/features/employees/data/models/employee_taught_class.dart';
import 'package:crm/features/employees/presentation/widgets/detail/back_link.dart';
import 'package:crm/features/employees/presentation/widgets/detail/employee_about_section.dart';
import 'package:crm/features/employees/presentation/widgets/detail/employee_classes_section.dart';
import 'package:crm/features/employees/presentation/widgets/detail/employee_info_section.dart';
import 'package:crm/features/employees/presentation/widgets/detail/employee_profile_header.dart';
import 'package:crm/shared/widgets/hairline.dart';
import 'package:crm/shared/widgets/subtitle_section.dart';

/// The employee profile: back link, header, then de-carded sections separated
/// by hairlines. Teaching + about sections appear only when there's real data
/// (the employee teaches at least one class, or has a bio), so a support-staff
/// profile stays honest instead of showing empty stats.
class EmployeeProfile extends StatelessWidget {
  final Employee employee;
  final List<EmployeeTaughtClass> taughtClasses;

  const EmployeeProfile({
    super.key,
    required this.employee,
    required this.taughtClasses,
  });

  @override
  Widget build(BuildContext context) {
    final bio = employee.employeePublicDescription;
    final hasBio = bio != null && bio.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        BackLink(onTap: () => _onBack(context)),
        EmployeeProfileHeader(employee: employee),
        const Hairline(),
        SubtitleSection(
          title: 'Info',
          child: EmployeeInfoSection(employee: employee),
        ),
        if (hasBio) ...[
          const Hairline(),
          SubtitleSection(
            title: 'About',
            child: EmployeeAboutSection(bio: bio.trim()),
          ),
        ],
        if (taughtClasses.isNotEmpty) ...[
          const Hairline(),
          SubtitleSection(
            title: 'Classes taught',
            child: EmployeeClassesSection(classes: taughtClasses),
          ),
        ],
      ],
    );
  }

  void _onBack(BuildContext context) {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacementNamed(context, AppRoutes.employees);
    }
  }
}
