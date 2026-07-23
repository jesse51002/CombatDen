import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/employees/data/models/employee.dart';
import 'package:crm/features/employees/presentation/dialogs/edit_employee_dialog.dart';
import 'package:crm/features/employees/presentation/dialogs/remove_employee_dialog.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/class_row/instructor_avatar.dart';
import 'package:crm/shared/widgets/employee_status_chip.dart';

/// Top of the employee detail page: large headshot, name, role + status chip,
/// and (when present) a copyable email, followed by the staff actions.
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
              photoUrl: employee.employeePicUrl,
              name: employee.fullName,
              diameter: 96,
            ),
            Expanded(child: _Identity(employee: employee)),
          ],
        ),
        _ActionButtons(employee: employee),
      ],
    );
  }
}

class _Identity extends StatelessWidget {
  final Employee employee;

  const _Identity({required this.employee});

  @override
  Widget build(BuildContext context) {
    final email = employee.email;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(employee.fullName, style: DesignConstants.big2Bold),
        Row(
          spacing: DesignConstants.spacingMedium,
          children: [
            Text(
              employee.employeeType.label,
              style: DesignConstants.h2.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
            EmployeeStatusChip(status: employee.inviteStatus),
          ],
        ),
        if (email != null && email.isNotEmpty) _EmailLine(email: email),
      ],
    );
  }
}

/// The email with a copy-to-clipboard affordance (icon swaps to a check for
/// ~2s after a copy).
class _EmailLine extends StatefulWidget {
  final String email;

  const _EmailLine({required this.email});

  @override
  State<_EmailLine> createState() => _EmailLineState();
}

class _EmailLineState extends State<_EmailLine> {
  bool _copied = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.email));
    if (!mounted) return;
    setState(() => _copied = true);
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(
          widget.email,
          style: DesignConstants.h3.copyWith(
            color: DesignConstants.hyperlink,
          ),
        ),
        InkWell(
          onTap: _copy,
          child: Icon(
            _copied ? Symbols.check_sharp : Symbols.content_copy_sharp,
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
  final Employee employee;

  const _ActionButtons({required this.employee});

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: DesignConstants.spacingLarge,
      children: [
        AppOutlineButton(
          text: 'Edit profile',
          onPressed: () => EditEmployeeDialog.show(
            context: context,
            employee: employee,
          ),
        ),
        // The owner row is never removable here (removing the seeded owner
        // would strand the gym) — hide the action rather than disable it.
        if (employee.employeeType != EmployeeRole.owner)
          AppOutlineButton(
            text: 'Remove',
            onPressed: () => RemoveEmployeeDialog.show(
              context: context,
              employee: employee,
            ),
          ),
      ],
    );
  }
}
