import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/home/bloc/live_attendance_bloc.dart';
import 'package:crm/features/home/bloc/live_attendance_event.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/error_message.dart';

/// Loading (null message) / empty / select-gym chrome for the Live
/// Attendance card. Mirrors the Upcoming Classes card's states.
class LiveAttendanceMessage extends StatelessWidget {
  final String? message;

  const LiveAttendanceMessage(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(DesignConstants.paddingBig),
      child: Center(
        child: message == null
            ? const AppSpinner()
            : Text(
                message!,
                style: DesignConstants.p.copyWith(
                  color: DesignConstants.text2nd,
                ),
                textAlign: TextAlign.center,
              ),
      ),
    );
  }
}

/// Error chrome with a retry that re-dispatches the load for [gymId].
class LiveAttendanceErrorBody extends StatelessWidget {
  final String gymId;

  const LiveAttendanceErrorBody({required this.gymId, super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        const ErrorMessage(message: 'Could not load live attendance.'),
        TextButton(
          onPressed: () => context
              .read<LiveAttendanceBloc>()
              .add(LiveAttendanceLoadRequested(gymId)),
          child: Text(
            'Retry',
            style: DesignConstants.h3.copyWith(
              color: DesignConstants.primaryColor,
            ),
          ),
        ),
      ],
    );
  }
}
