import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import 'package:crm/core/auth/role_policy.dart';
import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/core/navigation/nav_pop.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/employees/data/models/employee.dart';
import 'package:crm/features/employees/data/repositories/employees_repository.dart';
import 'package:crm/features/schedule/bloc/schedule_bloc.dart';
import 'package:crm/features/schedule/bloc/schedule_event.dart';
import 'package:crm/features/schedule/bloc/schedule_state.dart';
import 'package:crm/features/schedule/data/class_time_format.dart';
import 'package:crm/features/schedule/data/models/class_range_exception.dart';
import 'package:crm/features/schedule/data/models/gym_class_response.dart';
import 'package:crm/features/schedule/data/models/gym_class_view_models.dart';
import 'package:crm/features/schedule/data/occurrence_windows.dart';
import 'package:crm/features/schedule/data/models/instructor_option.dart';
import 'package:crm/features/schedule/data/range_exception_helpers.dart';
import 'package:crm/features/schedule/presentation/dialogs/check_in/class_batch_check_in_dialog.dart';
import 'package:crm/features/schedule/presentation/dialogs/class_move_day_dialog.dart';
import 'package:crm/features/schedule/presentation/dialogs/class_range_dates_dialog.dart';
import 'package:crm/features/schedule/presentation/dialogs/schedule_cancel_views.dart';
import 'package:crm/features/schedule/presentation/dialogs/signup/class_signup_dialog.dart';
import 'package:crm/features/schedule/presentation/widgets/form/class_attendee_roster.dart';
import 'package:crm/features/schedule/presentation/widgets/form/class_occurrence_actions.dart';
import 'package:crm/features/schedule/presentation/widgets/occurrence/class_occurrence_cancelling_range_section.dart';
import 'package:crm/features/schedule/presentation/widgets/occurrence/class_occurrence_header.dart';
import 'package:crm/features/schedule/presentation/widgets/occurrence/class_occurrence_override_section.dart';
import 'package:crm/features/schedule/presentation/widgets/occurrence/class_occurrence_read_only_details.dart';
import 'package:crm/features/schedule/presentation/widgets/occurrence/class_occurrence_staff_actions.dart';
import 'package:crm/features/schedule/presentation/widgets/occurrence/occurrence_mutation_overlay.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_shell.dart';
import 'package:crm/shared/widgets/confirmation_modal.dart';
import 'package:crm/shared/widgets/error_message.dart';

/// Full, human date used in the "class moved to …" success copy.
final DateFormat _movedDateLabel = DateFormat('EEEE, MMM d, yyyy');

/// Which mutation the screen is running (drives the success copy).
///
/// [override] / [cancelInstance] are the owner/admin `exceptions/instance`
/// paths; [cancelOccurrence] / [moveOccurrence] are the front-desk DEDICATED
/// occurrence endpoints.
enum _Action {
  override,
  cancelInstance,
  editRange,
  removeRangeCancellation,
  cancelOccurrence,
  moveOccurrence,
}

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
/// read-only by default (`ClassOccurrenceReadOnlyDetails`: an "Edit" button
/// switches modes, and, next to it, a destructive-styled "Cancel this class"
/// button when the occurrence is still cancellable) or the editable override
/// section (instructor / start time / max capacity / date for just this day,
/// pre-filled from [entry]'s effective values, plus a Cancel affordance back
/// to the read-only view) whose Save dispatches `ScheduleInstanceOverridden`;
/// the relocated `ClassOccurrenceActions` block (reserve members / update
/// attendees / the past-occurrence attendee roster). A cancelled occurrence
/// collapses to just that block's note. While a mutation + reload run, the
/// real content stays rendered under a dimmed [OccurrenceMutationOverlay]
/// (see [build]) so the terminal success dialog appears over it, not a blank
/// spinner page.
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
  late bool _capacityEnabled;
  final _capacityController = TextEditingController();
  final _durationController = TextEditingController();

  _Step _step = _Step.idle;
  _DetailsMode _mode = _DetailsMode.view;
  _Action _action = _Action.override;
  String? _inlineError;
  int _successBaseline = 0;
  bool _completing = false;

  /// The day a front-desk "Move to another day" is heading to — captured
  /// before dispatch so the success copy can name it. Only read for
  /// [_Action.moveOccurrence].
  DateTime? _movedToDate;

  /// The gym's staff roster, side-read once so the override's instructor
  /// picker lists real employees (not only instructors already assigned on a
  /// class), matching the class-definition form. Best-effort: a failure leaves
  /// it empty and the picker falls back to the from-classes instructors. Only
  /// the owner/admin override path renders the picker.
  List<Employee> _employees = const [];

  /// Editing the schedule (single-occurrence override, cancel, range ops) is
  /// owner/admin only.
  bool get _canEditSchedule => selectedGym.role?.canEditSchedule ?? false;

  /// The two DEDICATED single-occurrence staff ops (cancel + move to another
  /// day) are open to owner/admin/front desk. They render ONLY for the reduced
  /// (front-desk) surface — `... && !_canEditSchedule` — so owner/admin keep
  /// only their full override form and never get a duplicate affordance.
  bool get _canEditSingleOccurrence =>
      selectedGym.role?.canEditSingleOccurrence ?? false;

  /// Whether to render the reduced front-desk cancel/move block: the caller may
  /// run the dedicated occurrence ops but is NOT an owner/admin (who edit via
  /// the override form), and the occurrence isn't already cancelled.
  bool get _showStaffOccurrenceActions =>
      _canEditSingleOccurrence &&
      !_canEditSchedule &&
      !widget.entry.isCancelled;

  /// Check-in / reservation / roster-remove actions are open to
  /// owner/admin/front desk; a trainer's occurrence view is read-only.
  bool get _canCheckInMembers =>
      selectedGym.role?.canCheckInMembers ?? false;

  @override
  void initState() {
    super.initState();
    _resetFields();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    final gymId = selectedGym.gymId;
    if (gymId == null || gymId.isEmpty) return;
    try {
      final employees =
          await EmployeesRepository(apiClient: ApiClient()).listEmployees(gymId);
      if (!mounted) return;
      setState(() => _employees = employees);
    } catch (_) {
      // Best-effort: the picker degrades to the from-classes instructors.
    }
  }

  @override
  void dispose() {
    _capacityController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  /// Resets the editable override fields to [widget.entry]'s current
  /// effective values — called on init and by [_cancelEdit] so backing out of
  /// edit mode without saving discards any in-progress changes.
  void _resetFields() {
    _instructorId = widget.entry.resolvedInstructorId;
    _classTime = parseHmsTime(widget.entry.resolvedClassTime);
    _capacityEnabled = widget.entry.maxCapacity != null;
    _capacityController.text = widget.entry.maxCapacity?.toString() ?? '';
    _durationController.text =
        widget.entry.resolvedDurationMinutes.toString();
    _selectedDate = widget.entry.classDate;
  }

  /// Whether this occurrence can be cancelled — any occurrence that isn't
  /// already cancelled, past OR future. No time window: the backend
  /// (`cancel_occurrence`) accepts any date, and cancelling a past day is a
  /// legitimate "this didn't actually happen" correction (it also wipes that
  /// day's attendance + points). Contrast [_canSignUp], which DOES gate on
  /// the start instant — you can't reserve a spot in a class that passed.
  bool get _cancellable => !widget.entry.isCancelled;

  /// Whether members can still be signed up for this occurrence — the
  /// FUTURE-side counterpart of [_checkInOpen]: available while the
  /// occurrence's start INSTANT is still ahead (never day-based — a class
  /// that already ran earlier today isn't reservable). The sign-up endpoint
  /// itself imposes no time gate, but offering to reserve a spot in an
  /// already-passed session wouldn't make sense. Gates on the
  /// backend-computed UTC [ScheduleClassEntry.occurredAt] — never a
  /// browser-local rebuild of the gym-local date + time fields, which skews
  /// when the admin's timezone differs from the gym's.
  bool get _canSignUp {
    if (widget.entry.isCancelled) return false;
    return widget.entry.occurredAt.isAfter(DateTime.now());
  }

  /// Whether check-in is open for this occurrence: its start is within the
  /// shared [kCheckInOpensHours] early window (or already started / passed);
  /// "Update attendees" is hidden further out. The backend enforces the same
  /// rule against the same [ScheduleClassEntry.occurredAt] instant.
  bool get _checkInOpen =>
      occurrenceCheckInOpen(widget.entry.occurredAt, DateTime.now());

  Widget? _rosterFor() {
    final gymId = selectedGym.gymId;
    // Shown for any non-cancelled occurrence — a FUTURE occurrence has no
    // attendance yet but can have reservations, so the roster (Reserved-only
    // until someone attends) must render for it too, not just past/today.
    if (gymId == null || widget.entry.isCancelled) {
      return null;
    }
    return ClassAttendeeRoster(
      gymId: gymId,
      classId: widget.entry.classId,
      occurrenceDate: widget.entry.originalDate,
      occurrenceTime: widget.entry.originalTime,
      canManage: _canCheckInMembers,
    );
  }

  int? _capacityOrNull() {
    if (!_capacityEnabled) return null;
    final t = _capacityController.text.trim();
    return t.isEmpty ? null : int.tryParse(t);
  }

  static bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _close() => popOrGoTo(context, AppRoutes.schedule);

  void _startEdit() => setState(() => _mode = _DetailsMode.edit);

  void _cancelEdit() {
    setState(() {
      _resetFields();
      _inlineError = null;
      _mode = _DetailsMode.view;
    });
  }

  Future<void> _save() async {
    final time = _classTime;
    if (time == null) {
      setState(() => _inlineError = 'Pick a start time.');
      return;
    }
    final duration = int.tryParse(_durationController.text.trim());
    if (duration == null || duration <= 0) {
      setState(() => _inlineError = 'Enter a duration in minutes.');
      return;
    }
    // Warn before a save the backend treats as an attendance-wiping move.
    // Mirrors the backend exactly, which decides by the new effective start
    // INSTANT, never the day: the save must actually SEND `new_date`
    // (picked != originalDate — a move-home omits it and never wipes), the
    // landing instant must have changed (re-sending the current effective
    // date+time is a backend no-op — the preserve-the-move re-save never
    // warns), the occurrence must have recorded check-ins, and the target
    // instant (picked date + the edited start time, local) must still be
    // ahead of now — so moving tonight's already-moved class to later
    // tonight warns too, while a landing already in the past keeps its
    // check-ins (re-dated) and stays silent.
    final checkIns = widget.entry.attendeeCount ?? 0;
    final sendsNewDate =
        !_isSameDate(_selectedDate, widget.entry.originalDate);
    final landingChanged =
        !_isSameDate(_selectedDate, widget.entry.classDate) ||
            time != parseHmsTime(widget.entry.resolvedClassTime);
    final targetStart = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      time.hour,
      time.minute,
    );
    if (sendsNewDate &&
        landingChanged &&
        checkIns > 0 &&
        targetStart.isAfter(DateTime.now())) {
      final confirmed = await ConfirmationModal.show(
        context: context,
        title: 'Move this class?',
        message: 'Moving it to a time that hasn\'t happened yet clears its '
            '$checkIns check-in${checkIns == 1 ? '' : 's'} and reverses '
            'their points. Reservations move with the class.',
        confirmLabel: 'Move class',
        confirmColor: DesignConstants.badRed,
      );
      if (!confirmed || !mounted) return;
    }
    final bloc = context.read<ScheduleBloc>();
    _action = _Action.override;
    // `newDate` is judged against the occurrence's ORIGINAL (identity) date,
    // not the displayed effective one: on an already-rescheduled occurrence
    // the picker sits on the effective date, and re-sending it preserves the
    // move (the upsert full-replaces the exception row — omitting new_date
    // would silently un-reschedule; the backend treats a re-sent unchanged
    // landing as a no-op move). Picking the original date back is the
    // explicit "move it back" action and sends null.
    final sameAsOriginal =
        _isSameDate(_selectedDate, widget.entry.originalDate);
    final newDate = sameAsOriginal ? null : _selectedDate;
    _beginMutation(bloc);
    bloc.add(ScheduleInstanceOverridden(
      classId: widget.entry.classId,
      originalDate: widget.entry.originalDate,
      originalTime: widget.entry.originalTime,
      newClassTime: formatTimeOfDayHms(time),
      newDurationMinutes: duration,
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
      occurrenceDate: widget.entry.originalDate,
      occurrenceTime: widget.entry.originalTime,
    );
  }

  void _signUpMembers() {
    final gymId = selectedGym.gymId;
    if (gymId == null) return;
    ClassSignupDialog.show(
      context: context,
      classId: widget.entry.classId,
      gymId: gymId,
      className: widget.entry.name,
      occurrenceDate: widget.entry.originalDate,
      occurrenceTime: widget.entry.originalTime,
    );
  }

  /// The cancel confirm's copy — states the real stakes when the occurrence
  /// has reservations / check-ins: cancelling deletes its reservations and
  /// reverses its check-ins (their points are removed).
  String get _cancelMessage {
    const base = 'Only this date is cancelled — other dates are not affected.';
    final signups = widget.entry.signupCount;
    final checkIns = widget.entry.attendeeCount ?? 0;
    final parts = <String>[
      if (signups > 0)
        'removes its $signups reservation${signups == 1 ? '' : 's'}',
      if (checkIns > 0)
        'reverses its $checkIns check-in${checkIns == 1 ? '' : 's'} '
            'and their points',
    ];
    if (parts.isEmpty) return base;
    return '$base Cancelling ${parts.join(' and ')}.';
  }

  Future<void> _cancelThisClass() async {
    final confirmed = await ConfirmationModal.show(
      context: context,
      title: 'Cancel this class?',
      message: _cancelMessage,
      confirmLabel: 'Cancel this class',
      confirmColor: DesignConstants.badRed,
    );
    if (!confirmed || !mounted) return;
    final bloc = context.read<ScheduleBloc>();
    _action = _Action.cancelInstance;
    _beginMutation(bloc);
    bloc.add(ScheduleInstanceCancelled(
      classId: widget.entry.classId,
      originalDate: widget.entry.originalDate,
      originalTime: widget.entry.originalTime,
    ));
  }

  /// Front-desk "Cancel this class" — the DEDICATED staff cancel endpoint
  /// (`ScheduleOccurrenceCancelled`), NOT the owner/admin `exceptions/instance`
  /// override [_cancelThisClass] rides. Same confirm copy ([_cancelMessage]),
  /// same processing → success/error terminal lifecycle as every other action.
  Future<void> _cancelOccurrence() async {
    final confirmed = await ConfirmationModal.show(
      context: context,
      title: 'Cancel this class?',
      message: _cancelMessage,
      confirmLabel: 'Cancel this class',
      confirmColor: DesignConstants.badRed,
    );
    if (!confirmed || !mounted) return;
    final bloc = context.read<ScheduleBloc>();
    _action = _Action.cancelOccurrence;
    _beginMutation(bloc);
    bloc.add(ScheduleOccurrenceCancelled(
      classId: widget.entry.classId,
      originalDate: widget.entry.originalDate,
      originalTime: widget.entry.originalTime,
    ));
  }

  /// Front-desk "Move to another day (same time)" — the DEDICATED staff
  /// reschedule endpoint (`ScheduleOccurrenceRescheduled`). Picks a new day
  /// (the endpoint moves only the date; the original start time is preserved),
  /// warns before a move the backend treats as check-in-wiping (a FUTURE
  /// target instant clears the occurrence's check-ins and reverses their
  /// points — same instant rule as the override path; a past/today target
  /// keeps them re-dated), then rides the shared processing → success/error
  /// terminal lifecycle. A 409 target-instant collision surfaces its `detail`
  /// as the inline error.
  Future<void> _moveOccurrence() async {
    final picked = await ClassMoveDayDialog.show(
      context: context,
      className: widget.entry.name,
      timeLabel: widget.entry.timeLabel,
      initialDate: widget.entry.classDate,
    );
    if (picked == null || !mounted) return;
    final checkIns = widget.entry.attendeeCount ?? 0;
    final time = parseHmsTime(widget.entry.resolvedClassTime);
    final targetStart = time == null
        ? null
        : DateTime(
            picked.year,
            picked.month,
            picked.day,
            time.hour,
            time.minute,
          );
    if (checkIns > 0 &&
        targetStart != null &&
        targetStart.isAfter(DateTime.now())) {
      final confirmed = await ConfirmationModal.show(
        context: context,
        title: 'Move this class?',
        message: 'Moving it to a time that hasn\'t happened yet clears its '
            '$checkIns check-in${checkIns == 1 ? '' : 's'} and reverses '
            'their points. Reservations move with the class.',
        confirmLabel: 'Move class',
        confirmColor: DesignConstants.badRed,
      );
      if (!confirmed || !mounted) return;
    }
    final bloc = context.read<ScheduleBloc>();
    _action = _Action.moveOccurrence;
    _movedToDate = picked;
    _beginMutation(bloc);
    bloc.add(ScheduleOccurrenceRescheduled(
      classId: widget.entry.classId,
      originalDate: widget.entry.originalDate,
      originalTime: widget.entry.originalTime,
      newDate: picked,
    ));
  }

  /// "Edit range" on the "Cancelled by a range" section: pick new dates for
  /// the governing [range], warn if the move WIDENS its coverage (newly
  /// covered upcoming dates lose their reservations/check-ins), then run the
  /// same mutation lifecycle as every other occurrence-screen action —
  /// success dialog, then pop back to the (now-reloaded) board, since a
  /// widened/narrowed/moved range can change whether THIS occurrence is
  /// still cancelled at all.
  Future<void> _editCancellingRange(ClassRangeException range) async {
    final picked = await ClassRangeDatesDialog.show(
      context: context,
      className: widget.entry.name,
      initialStart: range.startDate,
      initialEnd: range.endDate,
    );
    if (picked == null || !mounted) return;
    final (start, end) = picked;
    if (rangeWidensCoverage(
      oldStart: range.startDate,
      oldEnd: range.endDate,
      newStart: start,
      newEnd: end,
    )) {
      final confirmed = await ConfirmationModal.show(
        context: context,
        title: kRangeEditWidenTitle,
        message: kRangeEditWidenMessage,
        confirmLabel: kRangeEditWidenConfirmLabel,
        confirmColor: DesignConstants.badRed,
      );
      if (!confirmed || !mounted) return;
    }
    final bloc = context.read<ScheduleBloc>();
    _action = _Action.editRange;
    _beginMutation(bloc);
    bloc.add(ScheduleRangeExceptionUpdated(
      classId: widget.entry.classId,
      exceptionId: range.exceptionId,
      start: start,
      end: end,
    ));
  }

  /// "Remove range cancellation" on the "Cancelled by a range" section:
  /// confirm, then remove [range] outright — the covered dates (including
  /// this occurrence) come back on the schedule; anything already torn down
  /// while the range was active is NOT restored.
  Future<void> _removeRangeCancellation(ClassRangeException range) async {
    final confirmed = await ConfirmationModal.show(
      context: context,
      title: kRangeRemoveTitle,
      message: kRangeRemoveMessage,
      confirmLabel: kRangeRemoveConfirmLabel,
      confirmColor: DesignConstants.badRed,
    );
    if (!confirmed || !mounted) return;
    final bloc = context.read<ScheduleBloc>();
    _action = _Action.removeRangeCancellation;
    _beginMutation(bloc);
    bloc.add(ScheduleRangeExceptionDeleted(
      classId: widget.entry.classId,
      exceptionId: range.exceptionId,
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
    if (mounted) popOrGoTo(context, AppRoutes.schedule);
  }

  String get _successTitle => switch (_action) {
        _Action.override => 'Day updated',
        _Action.cancelInstance => 'Class cancelled',
        _Action.editRange => 'Range updated',
        _Action.removeRangeCancellation => 'Cancellation removed',
        _Action.cancelOccurrence => 'Class cancelled',
        _Action.moveOccurrence => 'Class moved',
      };

  String get _successMessage => switch (_action) {
        _Action.override => "This day's details are updated.",
        _Action.cancelInstance => 'This class is cancelled for that day.',
        _Action.editRange => 'The cancelled range now covers new dates.',
        _Action.removeRangeCancellation =>
          'This class\'s dates are back on the schedule.',
        _Action.cancelOccurrence => 'This class is cancelled for that day.',
        _Action.moveOccurrence => _movedToDate != null
            ? 'This class moved to ${_movedDateLabel.format(_movedToDate!)}. '
                'The time stays the same.'
            : 'This class moved to another day. The time stays the same.',
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
              _content(InstructorOption.merged(_employees, classes)),
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
          if (!widget.entry.isCancelled)
            _detailsSection(instructors)
          else if (widget.entry.cancellingRangeId case final rangeId?)
            ClassOccurrenceCancellingRangeSection(
              classId: widget.entry.classId,
              cancellingRangeId: rangeId,
              canEdit: _canEditSchedule,
              onEdit: _editCancellingRange,
              onRemove: _removeRangeCancellation,
            ),
          if (_showStaffOccurrenceActions)
            ClassOccurrenceStaffActions(
              onMoveDay: _moveOccurrence,
              onCancel: _cancelOccurrence,
            ),
          ClassOccurrenceActions(
            occurrenceDate: widget.entry.classDate,
            isCancelled: widget.entry.isCancelled,
            canSignUp: _canSignUp,
            onSignUpMembers: _signUpMembers,
            canCheckIn: _checkInOpen,
            onUpdateAttendees: _updateAttendees,
            canManage: _canCheckInMembers,
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
          canEdit: _canEditSchedule,
          cancellable: _cancellable,
          onCancel: _cancelThisClass,
        ),
      _DetailsMode.edit => ClassOccurrenceOverrideSection(
          instructorId: _instructorId,
          onInstructorChanged: (id) => setState(() => _instructorId = id),
          instructors: instructors,
          classTime: _classTime,
          onTimeChanged: (t) => setState(() => _classTime = t),
          durationController: _durationController,
          capacityController: _capacityController,
          capacityEnabled: _capacityEnabled,
          onCapacityEnabledChanged: (v) =>
              setState(() => _capacityEnabled = v),
          selectedDate: _selectedDate,
          onDateChanged: (d) => setState(() => _selectedDate = d),
          onSave: _save,
          onCancel: _cancelEdit,
        ),
    };
  }
}
