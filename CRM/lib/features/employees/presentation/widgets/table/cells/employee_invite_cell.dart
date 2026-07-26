import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/employees/bloc/employees_bloc.dart';
import 'package:crm/features/employees/bloc/employees_event.dart';
import 'package:crm/features/employees/data/models/employee.dart';
import 'package:crm/features/employees/data/models/invite_status.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/employee_status_chip.dart';

/// The Status column: the login-status badge, plus a "Resend invite" link for
/// a row still waiting on one.
///
/// The affordance sits ON the badge that states the problem — `pending` means
/// the row exists but nobody has a login yet, and the usual reason is that the
/// email never landed. `active` needs nothing (they're in) and `none` has no
/// address to write to, so neither offers it.
///
/// The link swallows its own tap, so pressing it never also opens the row's
/// detail page.
class EmployeeInviteCell extends StatelessWidget {
  final Employee employee;

  /// True while this row's resend is in flight.
  final bool resending;

  /// True while ANY row's resend is in flight — the others go inert so a
  /// second send can't stack on the first.
  final bool anyResending;

  const EmployeeInviteCell({
    super.key,
    required this.employee,
    required this.resending,
    required this.anyResending,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        EmployeeStatusChip(status: employee.inviteStatus),
        if (employee.inviteStatus == InviteStatus.pending)
          resending
              ? const SizedBox(
                  height: DesignConstants.iconSizeMedium,
                  width: DesignConstants.iconSizeMedium,
                  child: AppSpinner(),
                )
              : _ResendLink(
                  enabled: !anyResending,
                  onTap: () => context.read<EmployeesBloc>().add(
                        EmployeeInviteResendRequested(employee.employeeId),
                      ),
                ),
      ],
    );
  }
}

class _ResendLink extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;

  const _ResendLink({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? DesignConstants.primaryColor
        : DesignConstants.text3rd;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.spacingSmall,
          vertical: DesignConstants.spacingTiny,
        ),
        child: Text(
          'Resend invite',
          style: DesignConstants.pSmall.copyWith(color: color),
        ),
      ),
    );
  }
}
