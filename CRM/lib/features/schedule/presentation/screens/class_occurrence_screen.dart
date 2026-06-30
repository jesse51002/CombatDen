import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/schedule/bloc/schedule_bloc.dart';
import 'package:crm/features/schedule/bloc/schedule_event.dart';
import 'package:crm/features/schedule/bloc/schedule_state.dart';
import 'package:crm/features/schedule/data/class_time_format.dart';
import 'package:crm/features/schedule/data/models/gym_class_response.dart';
import 'package:crm/features/schedule/data/models/gym_class_view_models.dart';
import 'package:crm/features/schedule/data/models/instructor_option.dart';
import 'package:crm/features/schedule/presentation/dialogs/check_in/class_batch_check_in_dialog.dart';
import 'package:crm/features/schedule/presentation/dialogs/schedule_cancel_views.dart';
import 'package:crm/features/schedule/presentation/widgets/form/class_attendee_roster.dart';
import 'package:crm/features/schedule/presentation/widgets/form/class_occurrence_actions.dart';
import 'package:crm/features/schedule/presentation/widgets/occurrence/class_occurrence_header.dart';
import 'package:crm/features/schedule/presentation/widgets/occurrence/class_occurrence_override_section.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_shell.dart';
import 'package:crm/shared/widgets/centered_processing_view.dart';
import 'package:crm/shared/widgets/confirmation_modal.dart';
import 'package:crm/shared/widgets/error_message.dart';

/// Which mutation the screen is running (drives the success copy).
enum _Action { override, cancelInstance }

/// The screen's run state: edit, or processing (a spinner) while a mutation +
/// board reload run. Mirrors `class_form_screen.dart`'s `_Step`.
enum _Step { editing, processing }

/// Single-occurrence screen, opened from the chooser dialog's "This
/// occurrence" option, sharing the board's [ScheduleBloc] (via
/// `BlocProvider.value`). Hosts: an override-edit section (instructor / start
/// time / max capacity for just this day, pre-filled from [entry]'s effective
/// values) whose Save dispatches `ScheduleInstanceOverridden`; the relocated
/// `ClassOccurrenceActions` block (update attendees / cancel this day / the
/// past-occurrence attendee roster). A cancelled occurrence collapses to just
/// that block's note.
class ClassOccurrenceScreen extends StatefulWidget {
  final ScheduleClassEntry entry;

  const ClassOccurrenceScreen({super.key, required this.entry});

  @override
  State<ClassOccurrenceScreen> createState() => _ClassOccurrenceScreenState();
}

class _ClassOccurrenceScreenState extends State<ClassOccurrenceScreen> {
  late String? _instructorId;
  late TimeOfDay? _classTime;
  final _capacityController = TextEditingController();

  _Step _step = _Step.editing;
  _Action _action = _Action.override;
  String? _inlineError;
  int _successBaseline = 0;
  bool _completing = false;

  @override
  void initState() {
    super.initState();
    _instructorId = widget.entry.resolvedInstructorId;
    _classTime = parseHmsTime(widget.entry.resolvedClassTime);
    _capacityController.text = widget.entry.maxCapacity?.toString() ?? '';
  }

  @override
  void dispose() {
    _capacityController.dispose();
    super.dispose();
  }

  bool get _cancellable {
    if (widget.entry.isCancelled) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return !widget.entry.classDate.isBefore(today);
  }

  bool get _pastOrToday {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return !widget.entry.classDate.isAfter(today);
  }

  Widget? _rosterFor() {
    final gymId = selectedGym.gymId;
    if (gymId == null || widget.entry.isCancelled || !_pastOrToday) {
      return null;
    }
    return ClassAttendeeRoster(
      gymId: gymId,
      classId: widget.entry.classId,
      occurrenceDate: widget.entry.classDate,
    );
  }

  int? _capacityOrNull() {
    final t = _capacityController.text.trim();
    return t.isEmpty ? null : int.tryParse(t);
  }

  void _close() => Navigator.of(context).pop();

  void _save() {
    final time = _classTime;
    if (time == null) {
      setState(() => _inlineError = 'Pick a start time.');
      return;
    }
    final bloc = context.read<ScheduleBloc>();
    _action = _Action.override;
    _beginMutation(bloc);
    bloc.add(ScheduleInstanceOverridden(
      classId: widget.entry.classId,
      date: widget.entry.classDate,
      newClassTime: formatTimeOfDayHms(time),
      newDurationMinutes: widget.entry.resolvedDurationMinutes,
      newMaxCapacity: _capacityOrNull(),
      newInstructorId: _instructorId,
    ));
  }

  void _updateAttendees() {
    final gymId = selectedGym.gymId;
    if (gymId == null) return;
    ClassBatchCheckInDialog.show(
      context: context,
      classId: widget.entry.classId,
      gymId: gymId,
      className: widget.entry.name,
      occurrenceDate: widget.entry.classDate,
    );
  }

  Future<void> _cancelThisClass() async {
    final confirmed = await ConfirmationModal.show(
      context: context,
      title: 'Cancel this class?',
      message: 'Only this date is cancelled — other dates are not affected.',
      confirmLabel: 'Cancel this class',
      confirmColor: DesignConstants.badRed,
    );
    if (!confirmed || !mounted) return;
    final bloc = context.read<ScheduleBloc>();
    _action = _Action.cancelInstance;
    _beginMutation(bloc);
    bloc.add(ScheduleInstanceCancelled(
      classId: widget.entry.classId,
      date: widget.entry.classDate,
    ));
  }

  void _beginMutation(ScheduleBloc bloc) {
    final state = bloc.state;
    _successBaseline = state is ScheduleLoaded ? state.actionSuccessCount : 0;
    setState(() {
      _inlineError = null;
      _step = _Step.processing;
    });
  }

  void _onState(BuildContext context, ScheduleState state) {
    if (_step != _Step.processing || _completing) return;
    if (state is! ScheduleLoaded || state.isMutating) return;
    if (state.actionSuccessCount > _successBaseline) {
      _completing = true;
      _completeWithSuccessDialog();
    } else if (state.actionError != null) {
      setState(() {
        _step = _Step.editing;
        _inlineError = state.actionError;
      });
    }
  }

  Future<void> _completeWithSuccessDialog() async {
    await AppDialog.show<void>(
      context: context,
      title: _successTitle,
      body: ScheduleCancelSuccess(message: _successMessage),
      primaryLabel: 'Done',
      primaryOnPressed: (ctx) => Navigator.of(ctx).pop(),
      secondaryLabel: null,
    );
    if (mounted) Navigator.of(context).pop();
  }

  String get _successTitle => switch (_action) {
        _Action.override => 'Day updated',
        _Action.cancelInstance => 'Class cancelled',
      };

  String get _successMessage => switch (_action) {
        _Action.override => "This day's details are updated.",
        _Action.cancelInstance => 'This class is cancelled for that day.',
      };

  @override
  Widget build(BuildContext context) {
    return AppShell(
      activeRoute: AppRoutes.schedule,
      child: BlocConsumer<ScheduleBloc, ScheduleState>(
        listener: _onState,
        builder: (context, state) {
          switch (_step) {
            case _Step.processing:
              return const CenteredProcessingView();
            case _Step.editing:
              final classes = state is ScheduleLoaded
                  ? state.classes
                  : const <GymClassResponse>[];
              return _content(InstructorOption.fromClasses(classes));
          }
        },
      ),
    );
  }

  Widget _content(List<InstructorOption> instructors) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(DesignConstants.paddingBig),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingBig,
        children: [
          ClassOccurrenceHeader(
            className: widget.entry.name,
            date: widget.entry.classDate,
            onBack: _close,
          ),
          if (_inlineError != null) ErrorMessage(message: _inlineError!),
          if (!widget.entry.isCancelled)
            ClassOccurrenceOverrideSection(
              instructorId: _instructorId,
              onInstructorChanged: (id) =>
                  setState(() => _instructorId = id),
              instructors: instructors,
              classTime: _classTime,
              onTimeChanged: (t) => setState(() => _classTime = t),
              capacityController: _capacityController,
              onSave: _save,
            ),
          ClassOccurrenceActions(
            occurrenceDate: widget.entry.classDate,
            cancellable: _cancellable,
            isCancelled: widget.entry.isCancelled,
            onUpdateAttendees: _updateAttendees,
            onCancelInstance: _cancelThisClass,
            roster: _rosterFor(),
          ),
        ],
      ),
    );
  }
}
