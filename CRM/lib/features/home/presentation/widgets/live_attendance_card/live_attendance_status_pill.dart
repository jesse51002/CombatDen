import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// A roster row's attendance state on the Live Attendance card.
enum LiveAttendanceStatus {
  /// Has a recorded attendance row (incl. an early check-in on the
  /// next-class preview).
  checkedIn,

  /// Reserved but not checked in while the class is IN SESSION.
  notHere,

  /// Reserved for the not-yet-started next class (the preview) — not late,
  /// so neither green nor red.
  reserved,
}

/// Small status indicator at the right of an attendance row — a colored
/// vertical bar plus its label.
class LiveAttendanceStatusPill extends StatelessWidget {
  final LiveAttendanceStatus status;

  const LiveAttendanceStatusPill({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      LiveAttendanceStatus.checkedIn => DesignConstants.goodGreen,
      LiveAttendanceStatus.notHere => DesignConstants.badRed,
      LiveAttendanceStatus.reserved => DesignConstants.primaryColor,
    };
    final label = switch (status) {
      LiveAttendanceStatus.checkedIn => 'Checked In',
      LiveAttendanceStatus.notHere => 'Not Here',
      LiveAttendanceStatus.reserved => 'Reserved',
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
