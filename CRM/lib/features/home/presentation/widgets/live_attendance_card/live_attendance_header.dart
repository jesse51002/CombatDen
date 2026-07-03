import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/home/bloc/live_attendance_state.dart';

/// Title + optional summary line for the Live Attendance card. The summary
/// is derived from the loaded state via [summaryFor]; the loading / error
/// shells pass null and render the bare title.
class LiveAttendanceHeader extends StatelessWidget {
  final String? subtitle;

  const LiveAttendanceHeader({super.key, this.subtitle});

  /// The one-line summary under the title: live head-counts during a class,
  /// the fall-forward note otherwise.
  static String summaryFor(LiveAttendanceLoaded state) {
    if (state.isNextPreview) {
      return state.sections.isEmpty
          ? 'No class in session.'
          : 'No class in session — showing the next class.';
    }
    final checkedIn = state.checkedIn;
    final notArrived = state.notArrived;
    final expected = checkedIn + notArrived;
    final percent =
        expected == 0 ? 0 : ((checkedIn / expected) * 100).round();
    return '$checkedIn checked in, $notArrived not arrived '
        '($percent% attendance)';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text('Live Attendance', style: DesignConstants.h1),
        if (subtitle != null)
          Text(
            subtitle!,
            style: DesignConstants.h3.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
      ],
    );
  }
}
