import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/features/employees/data/models/employee.dart';
import 'package:crm/features/employees/presentation/widgets/quick_list/employee_list_item.dart';
import 'package:crm/shared/widgets/app_search_box.dart';

/// Right-side rail on the employee detail screen — jump between employees
/// without returning to the full list. A local search narrows the rail; each
/// row deep-links to that employee's detail page.
class EmployeeQuickList extends StatefulWidget {
  final List<Employee> employees;
  final String selectedId;

  const EmployeeQuickList({
    super.key,
    required this.employees,
    required this.selectedId,
  });

  @override
  State<EmployeeQuickList> createState() => _EmployeeQuickListState();
}

class _EmployeeQuickListState extends State<EmployeeQuickList> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Employee> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.employees;
    return widget.employees
        .where((e) =>
            e.fullName.toLowerCase().contains(q) ||
            e.employeeType.label.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: DesignConstants.quickListWidth,
      padding: const EdgeInsets.all(DesignConstants.paddingBig),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingBig,
        children: [
          AppSearchBox(
            hintText: 'search...',
            controller: _controller,
            onChanged: (q) => setState(() => _query = q),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: DesignConstants.spacingMedium,
                children: [
                  for (final employee in _filtered)
                    EmployeeListItem(
                      employee: employee,
                      isSelected: employee.employeeId == widget.selectedId,
                      onTap: () => Navigator.pushReplacementNamed(
                        context,
                        AppRoutes.employeeDetailPath(employee.employeeId),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
