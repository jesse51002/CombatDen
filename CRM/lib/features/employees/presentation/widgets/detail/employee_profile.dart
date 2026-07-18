import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/core/navigation/nav_pop.dart';
import 'package:crm/features/employees/data/mock_employees.dart';
import 'package:crm/features/employees/presentation/widgets/detail/employee_about_section.dart';
import 'package:crm/features/employees/presentation/widgets/detail/employee_classes_section.dart';
import 'package:crm/features/employees/presentation/widgets/detail/employee_glance_section.dart';
import 'package:crm/features/employees/presentation/widgets/detail/employee_info_section.dart';
import 'package:crm/features/employees/presentation/widgets/detail/employee_profile_header.dart';
import 'package:crm/features/employees/presentation/widgets/detail/back_link.dart';
import 'package:crm/shared/widgets/hairline.dart';
import 'package:crm/shared/widgets/subtitle_section.dart';

/// The employee profile: back link, header, then de-carded sections separated
/// by hairlines. Coaching-only sections (At a glance, Specialties, Classes
/// taught) appear only when the employee actually coaches, so a front-desk
/// profile stays honest instead of showing empty teaching stats.
class EmployeeProfile extends StatelessWidget {
  final Employee employee;

  const EmployeeProfile({super.key, required this.employee});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        BackLink(onTap: () => popOrGoTo(context, AppRoutes.employees)),
        EmployeeProfileHeader(employee: employee),
        const Hairline(),
        SubtitleSection(
          title: 'Info',
          child: EmployeeInfoSection(employee: employee),
        ),
        if (employee.classesPerWeek != null) ...[
          const Hairline(),
          SubtitleSection(
            title: 'At a glance',
            child: EmployeeGlanceSection(employee: employee),
          ),
        ],
        const Hairline(),
        SubtitleSection(
          title: 'About',
          child: EmployeeAboutSection(bio: employee.bio),
        ),
        if (employee.classesTaught.isNotEmpty) ...[
          const Hairline(),
          SubtitleSection(
            title: 'Classes taught',
            child: EmployeeClassesSection(classes: employee.classesTaught),
          ),
        ],
      ],
    );
  }
}
