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
import 'package:crm/features/schedule/presentation/widgets/occurrence/class_occurrence_read_only_details.dart';
import 'package:crm/features/schedule/presentation/widgets/occurrence/occurrence_mutation_overlay.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_shell.dart';
import 'package:crm/shared/widgets/confirmation_modal.dart';
import 'package:crm/shared/widgets/error_message.dart';

/// Check-in opens this many hours before a class starts (mirrors the backend
/// `checkin_opens_hours_before_start`); "Update attendees" is hidden for an
/// occurrence further out than this — 2h so back-to-back classes can be checked
/// in together.
const int _kCheckInOpensHours = 2;

/// Which mutation the screen is running (drives the success copy).
enum _Action { override, cancelInstance }

/// The screen's run state: idle, or processing (a mutation + board reload in
/// flight). Only gates the [OccurrenceMutationOverlay] now — the real content
/// stays on screen throughout (see [build]).
enum _Step { idle, processing }

/// Whether "This day's details" shows the read-only view or the editable
/// override form. Defaults to [view]: a tapped occurrence is opened to be
/// SEEN first, not dropped straight into an editable form.
enum _DetailsMode { view, edit }

/// Single-occurrence screen, opened from the chooser dialog's "This
/// occurrence" option, sharing the board's [ScheduleBloc] (via
/// `BlocProvider.value`). Hosts: a view/edit **"This day's details"** block —
/// read-only by default (`ClassOccurrenceReadOnlyDetails`, an Edit button
/// switches modes) or the editable override section (instructor / start time
/// / max capacity / date for just this day, pre-filled from [entry]'s
/// effective values, plus a Cancel affordance back to the read-only view)
/// whose Save dispatches `ScheduleInstanceOverridden`; the relocated
/// `ClassOccurrenceActions` block (update attendees / cancel this day / the
/// past-occurrence attendee roster). A cancelled occurrence collapses to just
/// that block's note. While a mutation + reload run, the real content stays
/// rendered under a dimmed [OccurrenceMutationOverlay] (see [build]) so the
/// terminal success dialog appears over it, not a blank spinner page.
class ClassOccurrenceScreen extends StatefulWidget {
  final ScheduleClassEntry entry;

  const ClassOccurrenceScreen({super.key, required this.entry});

  @override
  State<ClassOccurrenceScreen> createState() => _ClassOccurrenceScreenState();
}

class _ClassOccurrenceScreenState extends State<ClassOccurrenceScreen> {
  late String? _instructorId;
  late TimeOfDay? _classTime;
  late DateTime _selectedDate;
  final _capacityController = TextEditingController();

  _Step _step = _Step.idle;
  _DetailsMode _mode = _DetailsMode.view;
  _Action _action = _Action.override;
  String? _inlineError;
  int _successBaseline = 0;
  bool _completing = false;

  @override
  void initState() {
    super.initState();
    _resetFields();
  }

  @override
  void dispose() {
    _capacityController.dispose();
    super.dispose();
  }

  /// Resets the editable override fields to [widget.entry]'s current
  /// effective values — called on init and by [_cancelEdit] so backing out of
  /// edit mode without saving discards any in-progress changes.
  void _resetFields() {
    _instructorId = widget.entry.resolvedInstructorId;
    _classTime = parseHmsTime(widget.entry.resolvedClassTime);
    _capacityController.text = widget.entry.maxCapacity?.toString() ?? '';
    _selectedDate = widget.entry.classDate;
  }

  bool get _cancellable {
    if (widget.entry.isCancelled) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return !widget.entry.classDate.isBefore(today);
  }

  /// Whether check-in is open for this occurrence: its start is within the
  /// early window (or already started / passed). The backend enforces the
  /// same rule.
  bool get _checkInOpen {
    final time = _classTime;
    if (time == null) return true;
    final start = DateTime(
      widget.entry.classDate.year,
      widget.entry.classDate.month,
      widget.entry.classDate.day,
      time.hour,
      time.minute,
    );
    return !start.isAfter(
      DateTime.now().add(const Duration(hours: _kCheckInOpensHours)),
    );
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

  static bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _close() => Navigator.of(context).pop();

  void _startEdit() => setState(() => _mode = _DetailsMode.edit);

  void _cancelEdit() {
    setState(() {
      _resetFields();
      _inlineError = null;
      _mode = _DetailsMode.view;
    });
  }

  void _save() {
    final time = _classTime;
    if (time == null) {
      setState(() => _inlineError = 'Pick a start time.');
      return;
    }
    final bloc = context.read<ScheduleBloc>();
    _action = _Action.override;
    // Only send `newDate` when the user actually picked a different (later)
    // date — leaving the picker on the occurrence's original date is a plain
    // retime/instructor/capacity override, not a reschedule.
    final sameDate = _isSameDate(_selectedDate, widget.entry.classDate);
    final newDate = sameDate ? null : _selectedDate;
    _beginMutation(bloc);
    bloc.add(ScheduleInstanceOverridden(
      classId: widget.entry.classId,
      date: widget.entry.classDate,
      newClassTime: formatTimeOfDayHms(time),
      newDurationMinutes: widget.entry.resolvedDurationMinutes,
      newMaxCapacity: _capacityOrNull(),
      newInstructorId: _instructorId,
      newDate: newDate,
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
        _step = _Step.idle;
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
          final classes = state is ScheduleLoaded
              ? state.classes
              : const <GymClassResponse>[];
          // The content always renders (never swapped for a full-screen
          // spinner) so a processing/success/error overlay sits ON TOP of it
          // — the success `AppDialog` then appears over real content, not a
          // blank page.
          return Stack(
            children: [
              _content(InstructorOption.fromClasses(classes)),
              if (_step == _Step.processing)
                const Positioned.fill(child: OccurrenceMutationOverlay()),
            ],
          );
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
            imageUrl: widget.entry.imageUrl,
            onBack: _close,
          ),
          if (_inlineError != null) ErrorMessage(message: _inlineError!),
          if (!widget.entry.isCancelled) _detailsSection(instructors),
          ClassOccurrenceActions(
            occurrenceDate: widget.entry.classDate,
            cancellable: _cancellable,
            isCancelled: widget.entry.isCancelled,
            canCheckIn: _checkInOpen,
            onUpdateAttendees: _updateAttendees,
            onCancelInstance: _cancelThisClass,
            roster: _rosterFor(),
          ),
        ],
      ),
    );
  }

  Widget _detailsSection(List<InstructorOption> instructors) {
    return switch (_mode) {
      _DetailsMode.view => ClassOccurrenceReadOnlyDetails(
          entry: widget.entry,
          onEdit: _startEdit,
        ),
      _DetailsMode.edit => ClassOccurrenceOverrideSection(
          instructorId: _instructorId,
          onInstructorChanged: (id) => setState(() => _instructorId = id),
          instructors: instructors,
          classTime: _classTime,
          onTimeChanged: (t) => setState(() => _classTime = t),
          capacityController: _capacityController,
          originalDate: widget.entry.classDate,
          selectedDate: _selectedDate,
          onDateChanged: (d) => setState(() => _selectedDate = d),
          onSave: _save,
          onCancel: _cancelEdit,
        ),
    };
  }
}
