import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/presentation/widgets/member_detail_format.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';

/// Presentation-only helpers shared by the membership
/// carousel sections. Status colors, formatted cost /
/// duration strings, and small value widgets — kept here
/// so every membership surface reads the same and depends
/// only on [DesignConstants] tokens.

/// A muted label widget for an [InfoTable] row.
Widget membershipLabel(String text) {
  return Text(
    text,
    style: DesignConstants.h2.copyWith(
      color: DesignConstants.text2nd,
    ),
  );
}

/// The semantic color for a [MembershipStatus].
Color statusColor(MembershipStatus status) {
  return switch (status) {
    MembershipStatus.active => DesignConstants.goodGreen,
    MembershipStatus.trial => DesignConstants.goodGreen,
    MembershipStatus.frozen => DesignConstants.okYellow,
    MembershipStatus.overdue => DesignConstants.badRed,
    MembershipStatus.cancelled => DesignConstants.badRed,
    MembershipStatus.ended => DesignConstants.badRed,
    MembershipStatus.noMembership => DesignConstants.text2nd,
    MembershipStatus.unknown => DesignConstants.text,
  };
}

/// A colored status text widget.
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

/// Whether the membership is in a terminal state — billing
/// has stopped and per-membership mutations no longer apply.
bool isTerminalStatus(MembershipStatus status) =>
    status == MembershipStatus.cancelled ||
    status == MembershipStatus.ended;

/// Cost display from the membership's total price (minor
/// currency units).
Widget costValue(MembershipInfo membership) {
  return Text(
    formatMinorUnits(membership.totalPrice),
    style: DesignConstants.h2.copyWith(
      fontWeight: FontWeight.w700,
    ),
  );
}

/// The duration row label — "Billing Cycle:" for recurring
/// plans, "Duration:" otherwise.
String durationLabel(String? planType) {
  if (planType?.toLowerCase() == 'recurring') {
    return 'Billing Cycle:';
  }
  return 'Duration:';
}

/// Formats a plan's duration for display.
///
/// Recurring: frequency style — "Monthly", "Every 2 Months".
/// One-time / trial: amount style — "1 Month", "2 Weeks".
String formatDuration(
  int amount,
  String unit,
  String? planType,
) {
  final lower = unit.toLowerCase();
  final capitalised =
      lower.isEmpty ? unit : lower[0].toUpperCase() + lower.substring(1);
  if (planType?.toLowerCase() == 'recurring') {
    if (amount == 1) {
      return switch (lower) {
        'year' => 'Yearly',
        'month' => 'Monthly',
        'week' => 'Weekly',
        'day' => 'Daily',
        _ => 'Every $amount $capitalised',
      };
    }
    return 'Every $amount ${capitalised}s';
  }
  if (amount == 1) {
    return '$amount $capitalised';
  }
  return '$amount ${capitalised}s';
}

/// A formatted date value widget, or an em dash for null.
Widget dateValue(DateTime? date) {
  if (date == null) {
    return Text('—', style: DesignConstants.h2);
  }
  return Text(
    formatDay(date),
    style: DesignConstants.h2.copyWith(
      fontWeight: FontWeight.w700,
    ),
  );
}
