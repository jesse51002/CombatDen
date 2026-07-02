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
import 'package:crm/features/schedule/presentation/dialogs/signup/class_signup_dialog.dart';
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
    _capacityEnabled = widget.entry.maxCapacity != null;
    _capacityController.text = widget.entry.maxCapacity?.toString() ?? '';
    _selectedDate = widget.entry.classDate;
  }

  /// Whether this occurrence can be cancelled — any occurrence that isn't
  /// already cancelled, past OR future. No time window: the backend
  /// (`cancel_occurrence`) accepts any date, and cancelling a past day is a
  /// legitimate "this didn't actually happen" correction (it also wipes that
  /// day's attendance + points). Contrast [_canSignUp], which DOES keep a
  /// today-or-later window — you can't reserve a spot in a class that passed.
  bool get _cancellable => !widget.entry.isCancelled;

  /// Whether members can still be signed up for this occurrence — the
  /// FUTURE-side counterpart of [_checkInOpen]: available while the
  /// occurrence hasn't already passed (today or later). The sign-up endpoint
  /// itself imposes no time gate, but offering to reserve a spot in an
  /// already-passed session wouldn't make sense.
  bool get _canSignUp {
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
    );
  }

  int? _capacityOrNull() {
    if (!_capacityEnabled) return null;
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

  Future<void> _save() async {
    final time = _classTime;
    if (time == null) {
      setState(() => _inlineError = 'Pick a start time.');
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
      occurrenceDate: widget.entry.originalDate,
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
            isCancelled: widget.entry.isCancelled,
            canSignUp: _canSignUp,
            onSignUpMembers: _signUpMembers,
            canCheckIn: _checkInOpen,
            onUpdateAttendees: _updateAttendees,
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
          cancellable: _cancellable,
          onCancel: _cancelThisClass,
        ),
      _DetailsMode.edit => ClassOccurrenceOverrideSection(
          instructorId: _instructorId,
          onInstructorChanged: (id) => setState(() => _instructorId = id),
          instructors: instructors,
          classTime: _classTime,
          onTimeChanged: (t) => setState(() => _classTime = t),
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
