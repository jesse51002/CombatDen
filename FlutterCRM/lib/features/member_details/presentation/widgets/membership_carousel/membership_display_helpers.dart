import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';

/// Builds a label widget for info table rows.
Widget membershipLabel(String text) {
  return Text(
    text,
    style: DesignConstants.h2.copyWith(
      color: DesignConstants.text2nd,
    ),
  );
}

/// Returns the color for a [MembershipStatus].
Color statusColor(MembershipStatus status) {
  return switch (status) {
    MembershipStatus.active => DesignConstants.goodGreen,
    MembershipStatus.trial => DesignConstants.goodGreen,
    MembershipStatus.frozen => DesignConstants.okYellow,
    MembershipStatus.cancelled => DesignConstants.badRed,
    MembershipStatus.ended => DesignConstants.badRed,
    MembershipStatus.overdue => DesignConstants.badRed,
    MembershipStatus.noMembership =>
      DesignConstants.text2nd,
    MembershipStatus.unknown => DesignConstants.text,
  };
}

/// Builds a colored status text widget.
Widget statusValue(MembershipStatus status) {
  return Semantics(
    label: 'Membership status: ${status.displayLabel}',
    child: Text(
      status.displayLabel,
      style: DesignConstants.h2.copyWith(
        color: statusColor(status),
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// Builds a cost display from the membership's total price
/// (stored as minor currency units).
Widget costValue(MembershipInfo membership) {
  return Text(
    formatMinorUnits(membership.totalPrice),
    style: DesignConstants.h2.copyWith(
      fontWeight: FontWeight.w700,
    ),
  );
}

/// Returns the appropriate label for the duration row
/// based on the plan type.
String durationLabel(String? planType) {
  if (planType?.toLowerCase() == 'recurring') {
    return 'Billing Cycle:';
  }
  return 'Duration:';
}

/// Formats duration for display based on plan type.
///
/// Recurring: frequency style — "Monthly", "Every 2 Months"
/// One-time/trial: amount style — "1 Month", "2 Weeks"
String formatDuration(
  int amount,
  String unit,
  String? planType,
) {
  final lower = unit.toLowerCase();
  if (planType?.toLowerCase() == 'recurring') {
    if (amount == 1) {
      return switch (lower) {
        'year' => 'Yearly',
        'month' => 'Monthly',
        'week' => 'Weekly',
        'day' => 'Daily',
        _ => 'Every $amount '
            '${lower[0].toUpperCase()}${lower.substring(1)}',
      };
    }
    final capitalised =
        lower[0].toUpperCase() + lower.substring(1);
    final plural = '${capitalised}s';
    return 'Every $amount $plural';
  }
  final capitalised =
      lower[0].toUpperCase() + lower.substring(1);
  if (amount == 1) {
    return '$amount $capitalised';
  }
  return '$amount ${capitalised}s';
}

/// Builds a formatted date text or an em-dash for null.
Widget dateValue(DateTime? date, DateFormat fmt) {
  if (date == null) {
    return Text('—', style: DesignConstants.h2);
  }
  return Text(
    fmt.format(date.toLocal()),
    style: DesignConstants.h2.copyWith(
      fontWeight: FontWeight.w700,
    ),
  );
}
