import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/employees/data/models/invite_status.dart';

/// An employee's login status as a colored bar + label — the
/// `LiveAttendanceStatusPill` idiom (a `statusAccentBarHeight` vertical bar +
/// an `h3` label in the same color). Status is "colored text, never a filled
/// cell," so it reads identically in the table column and the detail header.
///
/// The status is backend-derived (the client can't check auth-account
/// existence): [InviteStatus.active] = a verified account matches the email;
/// [InviteStatus.pending] = an email with no verified account yet;
/// [InviteStatus.none] = no email (an email-less instructor).
class EmployeeStatusChip extends StatelessWidget {
  final InviteStatus status;

  const EmployeeStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      InviteStatus.active => (DesignConstants.goodGreen, 'Active'),
      InviteStatus.pending => (DesignConstants.primaryColor, 'Pending'),
      InviteStatus.none => (DesignConstants.text3rd, 'No login'),
      InviteStatus.unknown => (DesignConstants.text3rd, 'Unknown'),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        Container(
          width: 5,
          height: DesignConstants.statusAccentBarHeight,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
          ),
        ),
        Text(label, style: DesignConstants.h3.copyWith(color: color)),
      ],
    );
  }
}
