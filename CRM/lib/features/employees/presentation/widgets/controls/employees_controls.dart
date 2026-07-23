import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/employees/bloc/employees_bloc.dart';
import 'package:crm/features/employees/bloc/employees_event.dart';
import 'package:crm/features/employees/presentation/dialogs/add_employee_dialog.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/app_search_box.dart';
import 'package:crm/shared/widgets/filter_pills.dart';

/// Search box + "Add Employee" button + role-filter pills for the Employees
/// roster. Search + role changes dispatch to [EmployeesBloc]; the pills reflect
/// the bloc's current [roleFilter].
class EmployeesControls extends StatefulWidget {
  final EmployeeRole? roleFilter;

  const EmployeesControls({super.key, required this.roleFilter});

  @override
  State<EmployeesControls> createState() => _EmployeesControlsState();
}

class _EmployeesControlsState extends State<EmployeesControls> {
  final _searchController = TextEditingController();

  static const List<String> _pillLabels = [
    'All',
    'Admin',
    'Front Desk',
    'Trainer',
  ];
  static const List<EmployeeRole?> _pillRoles = [
    null,
    EmployeeRole.admin,
    EmployeeRole.frontDesk,
    EmployeeRole.trainer,
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _pillRoles.indexOf(widget.roleFilter);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Row(
          spacing: DesignConstants.spacingBig,
          children: [
            Expanded(
              child: AppSearchBox(
                hintText: ' search name or role...',
                controller: _searchController,
                onChanged: (q) => context
                    .read<EmployeesBloc>()
                    .add(EmployeesSearchChanged(q)),
              ),
            ),
            AppPrimaryButton(
              text: 'Add Employee',
              textStyle: DesignConstants.h2,
              padding: const EdgeInsets.symmetric(
                horizontal: DesignConstants.paddingBig,
                vertical: DesignConstants.spacingMedium,
              ),
              onPressed: () => AddEmployeeDialog.show(context: context),
            ),
          ],
        ),
        FilterPills(
          labels: _pillLabels,
          selectedIndex: selected < 0 ? 0 : selected,
          onSelected: (i) => context
              .read<EmployeesBloc>()
              .add(EmployeesRoleFilterChanged(_pillRoles[i])),
        ),
      ],
    );
  }
}
