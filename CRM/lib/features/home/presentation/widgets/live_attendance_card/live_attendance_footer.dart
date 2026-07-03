import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/features/home/bloc/live_attendance_bloc.dart';
import 'package:crm/features/home/bloc/live_attendance_event.dart';
import 'package:crm/features/home/data/live_attendance_section.dart';
import 'package:crm/features/schedule/bloc/schedule_bloc.dart';
import 'package:crm/features/schedule/bloc/schedule_state.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';
import 'package:crm/features/schedule/data/models/gym_class_view_models.dart';
import 'package:crm/features/schedule/presentation/dialogs/check_in/class_batch_check_in_dialog.dart';
import 'package:crm/features/schedule/presentation/screens/class_occurrence_screen.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';

/// Mirrors the backend `checkin_opens_hours_before_start` (and the
/// occurrence screen's own `_kCheckInOpensHours`).
const int _kCheckInOpensHours = 2;

/// Pinned action row under the roster, acting on [target] (the first shown
/// occurrence): "Check In Member" opens its batch check-in dialog,
/// "View all" opens its occurrence screen — both share the card's loaded
/// [ScheduleBloc] exactly as when opened from the board, and refresh the
/// card on return. Buttons disable until that bloc is loaded (its
/// mutation/check-in channels need a loaded state) or when nothing is
/// shown; check-in additionally waits for the class's 2h window.
class LiveAttendanceFooter extends StatelessWidget {
  final LiveAttendanceSection? target;

  const LiveAttendanceFooter({super.key, required this.target});

  /// Started already, or starts within the 2h early window — a next-class
  /// preview further out hides check-in (the backend rejects it anyway).
  bool _checkInOpen(EffectiveClassInstance instance) {
    final opensBoundary =
        DateTime.now().add(const Duration(hours: _kCheckInOpensHours));
    return !instance.occurredAt.isAfter(opensBoundary);
  }

  Future<void> _openBatchCheckIn(BuildContext context) async {
    final instance = target!.instance;
    await ClassBatchCheckInDialog.show(
      context: context,
      classId: instance.classId,
      gymId: instance.gymId,
      className: instance.className,
      occurrenceDate: instance.originalDate,
      occurrenceTime: instance.originalTime,
    );
    if (!context.mounted) return;
    context
        .read<LiveAttendanceBloc>()
        .add(const LiveAttendanceRefreshRequested());
  }

  Future<void> _openOccurrence(BuildContext context) async {
    final bloc = context.read<ScheduleBloc>();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: AppRoutes.scheduleOccurrence),
        builder: (_) => BlocProvider<ScheduleBloc>.value(
          value: bloc,
          child: ClassOccurrenceScreen(
            entry: ScheduleClassEntry.fromInstance(target!.instance),
          ),
        ),
      ),
    );
    if (!context.mounted) return;
    context
        .read<LiveAttendanceBloc>()
        .add(const LiveAttendanceRefreshRequested());
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ScheduleBloc, ScheduleState>(
      builder: (context, scheduleState) {
        final ready = target != null && scheduleState is ScheduleLoaded;
        final checkInOpen = ready && _checkInOpen(target!.instance);
        return Row(
          spacing: DesignConstants.spacingLarge,
          children: [
            Expanded(
              child: AppPrimaryButton(
                text: 'Check In Member',
                fullWidth: true,
                onPressed:
                    checkInOpen ? () => _openBatchCheckIn(context) : null,
              ),
            ),
            Expanded(
              child: AppOutlineButton(
                text: 'View all',
                fullWidth: true,
                onPressed: ready ? () => _openOccurrence(context) : null,
              ),
            ),
          ],
        );
      },
    );
  }
}
