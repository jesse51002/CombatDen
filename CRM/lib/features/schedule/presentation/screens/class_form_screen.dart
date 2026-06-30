import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/schedule/bloc/schedule_bloc.dart';
import 'package:crm/features/schedule/bloc/schedule_event.dart';
import 'package:crm/features/schedule/bloc/schedule_state.dart';
import 'package:crm/features/schedule/data/models/gym_class_create_request.dart';
import 'package:crm/features/schedule/data/models/gym_class_response.dart';
import 'package:crm/features/schedule/data/models/gym_class_update_request.dart';
import 'package:crm/features/schedule/data/models/instructor_option.dart';
import 'package:crm/features/schedule/data/models/recurring_unit.dart';
import 'package:crm/features/schedule/presentation/dialogs/check_in/class_batch_check_in_dialog.dart';
import 'package:crm/features/schedule/presentation/dialogs/class_range_cancel_dialog.dart';
import 'package:crm/features/schedule/presentation/dialogs/schedule_cancel_views.dart';
import 'package:crm/features/schedule/presentation/widgets/form/class_attendee_roster.dart';
import 'package:crm/features/schedule/presentation/widgets/form/class_days_section.dart';
import 'package:crm/features/schedule/presentation/widgets/form/class_details_section.dart';
import 'package:crm/features/schedule/presentation/widgets/form/class_form_actions.dart';
import 'package:crm/features/schedule/presentation/widgets/form/class_occurrence_actions.dart';
import 'package:crm/features/schedule/presentation/widgets/form/class_rewards_section.dart';
import 'package:crm/features/schedule/presentation/widgets/form/class_schedule_section.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_shell.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/confirmation_modal.dart';
import 'package:crm/shared/widgets/error_message.dart';

/// Which mutation the form is running (drives the success copy).
enum _ClassAction { create, update, delete, cancelInstance }

/// The form's run state: edit the fields, or processing (a spinner) while a
/// mutation + board reload run. A committed mutation surfaces a success
/// **dialog** over the spinner, then pops the form; a failure returns to
/// editing with an inline error (the Save button retries).
enum _Step { editing, processing }

/// Full-page Add/Edit Class form, wired live to the FastAPI `classes` domain
/// through the board's shared [ScheduleBloc] (provided by the caller via
/// `BlocProvider.value`). Saving dispatches `ScheduleClassCreated` /
/// `ScheduleClassUpdated`; deleting dispatches `ScheduleClassDeleted`. The
/// bloc reloads the board on success, so dismissing the confirmation drops the
/// user back onto an already-fresh schedule.
///
/// Pass [existing] (the real [GymClassResponse] from the board) to edit;
/// omit it to create.
///
/// When opened from a tapped board card the caller also passes
/// [occurrenceDate] (and [occurrenceCancelled]) — the form then hosts that
/// single occurrence's actions ("Update attendees" / "Cancel this class"),
/// replacing the old manage-occurrence popup.
class ClassFormScreen extends StatefulWidget {
  final GymClassResponse? existing;

  /// The tapped occurrence's effective local date; null for the header
  /// "Add class" path (a brand-new class has no occurrence yet).
  final DateTime? occurrenceDate;

  /// Whether the tapped occurrence is already cancelled for its day.
  final bool occurrenceCancelled;

  const ClassFormScreen({
    super.key,
    this.existing,
    this.occurrenceDate,
    this.occurrenceCancelled = false,
  });

  @override
  State<ClassFormScreen> createState() => _ClassFormScreenState();
}

class _ClassFormScreenState extends State<ClassFormScreen> {
  /// Backend `start_date` / `end_date` are bare `YYYY-MM-DD` (gym-local).
  static final DateFormat _dateParam = DateFormat('yyyy-MM-dd');

  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _pointsController = TextEditingController(text: '50');
  final _capacityController = TextEditingController();
  final _durationController = TextEditingController(text: '60');
  final _intervalController = TextEditingController(text: '1');

  TimeOfDay? _classTime;
  RecurringUnit _recurringUnit = RecurringUnit.weekly;
  DateTime? _startDate;
  DateTime? _endDate;
  Set<int> _selectedDays = {};
  Map<int, String?> _instructorByDay = {};
  String? _imageUrl;

  /// Carried through unchanged — the form has no allowed-plans UI yet.
  List<String>? _allowedPlanIds;

  _Step _step = _Step.editing;
  _ClassAction _action = _ClassAction.create;
  String? _inlineError;

  /// `actionSuccessCount` snapshot taken when a mutation is dispatched; a later
  /// increase means our write committed.
  int _successBaseline = 0;

  /// Latched once a committed mutation starts surfacing its success dialog, so
  /// the listener fires the terminal flow exactly once.
  bool _completing = false;

  bool get _isEdit => widget.existing != null;

  /// True when the form was opened from a tapped occurrence (edit + a date),
  /// so the single-occurrence actions block renders.
  bool get _hasOccurrence => _isEdit && widget.occurrenceDate != null;

  /// An upcoming, not-already-cancelled occurrence can be cancelled for its
  /// day (mirrors the retired manage-popup's `cancellable` gate).
  bool get _occurrenceCancellable {
    final date = widget.occurrenceDate;
    if (date == null || widget.occurrenceCancelled) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return !date.isBefore(today);
  }

  /// A past or current-day, non-cancelled occurrence is materialized (or
  /// materializable) — show its attendee roster. A future occurrence has no
  /// attendance yet, so the roster is hidden there.
  bool get _occurrencePastOrToday {
    final date = widget.occurrenceDate;
    if (date == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return !date.isAfter(today);
  }

  /// The attendee roster for a past / materialized occurrence, or null when it
  /// shouldn't render (future, cancelled, or no active gym).
  Widget? _rosterFor() {
    final existing = widget.existing;
    final date = widget.occurrenceDate;
    final gymId = selectedGym.gymId;
    if (existing == null || date == null || gymId == null) return null;
    if (widget.occurrenceCancelled || !_occurrencePastOrToday) return null;
    return ClassAttendeeRoster(
      gymId: gymId,
      classId: existing.classId,
      occurrenceDate: date,
    );
  }

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    if (c != null) _prefill(c);
  }

  void _prefill(GymClassResponse c) {
    _nameController.text = c.className;
    _descriptionController.text = c.classDescription ?? '';
    _pointsController.text = c.pointsWorth.toString();
    _capacityController.text = c.maxCapacity?.toString() ?? '';
    _durationController.text = c.durationMinutes.toString();
    _intervalController.text = c.recurringInterval.toString();
    _classTime = _parseTime(c.classTime);
    _recurringUnit = c.recurringUnit == RecurringUnit.unknown
        ? RecurringUnit.weekly
        : c.recurringUnit;
    _startDate = _dateOnly(c.startDate);
    _endDate = c.endDate == null ? null : _dateOnly(c.endDate!);
    _selectedDays = {
      if (c.sun) 0,
      if (c.mon) 1,
      if (c.tue) 2,
      if (c.wed) 3,
      if (c.thu) 4,
      if (c.fri) 5,
      if (c.sat) 6,
    };
    _instructorByDay = {
      0: c.sunInstructorId,
      1: c.monInstructorId,
      2: c.tueInstructorId,
      3: c.wedInstructorId,
      4: c.thuInstructorId,
      5: c.friInstructorId,
      6: c.satInstructorId,
    };
    _imageUrl = c.imageUrl;
    _allowedPlanIds = c.allowedPlanIds;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _pointsController.dispose();
    _capacityController.dispose();
    _durationController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  void _toggleDay(int day) {
    setState(() {
      if (_selectedDays.contains(day)) {
        _selectedDays.remove(day);
        _instructorByDay.remove(day);
      } else {
        _selectedDays.add(day);
      }
    });
  }

  void _close() => Navigator.of(context).pop();

  // ---- form-model <-> request conversions ---------------------------------

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// `HH:MM:SS` -> [TimeOfDay] (seconds ignored).
  static TimeOfDay? _parseTime(String hms) {
    final parts = hms.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  /// [TimeOfDay] -> `HH:MM:SS`.
  static String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:00';

  bool _day(int i) => _selectedDays.contains(i);

  /// The instructor for day [i] — only when that day is active.
  String? _instructorFor(int i) =>
      _selectedDays.contains(i) ? _instructorByDay[i] : null;

  String? _descriptionOrNull() {
    final t = _descriptionController.text.trim();
    return t.isEmpty ? null : t;
  }

  int? _capacityOrNull() {
    final t = _capacityController.text.trim();
    return t.isEmpty ? null : int.tryParse(t);
  }

  RecurringUnit get _safeUnit =>
      _recurringUnit == RecurringUnit.unknown
          ? RecurringUnit.weekly
          : _recurringUnit;

  /// Required-field check; returns a message to show inline, or null if valid.
  String? _validate() {
    if (_nameController.text.trim().isEmpty) return 'Enter a class name.';
    if (_classTime == null) return 'Pick a start time.';
    if (_startDate == null) return 'Pick a start date.';
    if (_selectedDays.isEmpty) return 'Select at least one day.';
    final duration = int.tryParse(_durationController.text.trim());
    if (duration == null || duration <= 0) return 'Enter a duration above 0.';
    final interval = int.tryParse(_intervalController.text.trim());
    if (interval == null || interval <= 0) return 'Enter an interval above 0.';
    final points = int.tryParse(_pointsController.text.trim());
    if (points == null || points <= 0) return 'Enter points above 0.';
    return null;
  }

  GymClassCreateRequest _buildCreate(String gymId) => GymClassCreateRequest(
        gymId: gymId,
        className: _nameController.text.trim(),
        classDescription: _descriptionOrNull(),
        classTime: _formatTime(_classTime!),
        durationMinutes: int.parse(_durationController.text.trim()),
        recurringUnit: _safeUnit,
        recurringInterval: int.parse(_intervalController.text.trim()),
        sun: _day(0),
        mon: _day(1),
        tue: _day(2),
        wed: _day(3),
        thu: _day(4),
        fri: _day(5),
        sat: _day(6),
        sunInstructorId: _instructorFor(0),
        monInstructorId: _instructorFor(1),
        tueInstructorId: _instructorFor(2),
        wedInstructorId: _instructorFor(3),
        thuInstructorId: _instructorFor(4),
        friInstructorId: _instructorFor(5),
        satInstructorId: _instructorFor(6),
        startDate: _dateParam.format(_startDate!),
        endDate: _endDate == null ? null : _dateParam.format(_endDate!),
        maxCapacity: _capacityOrNull(),
        allowedPlanIds: _allowedPlanIds,
        imageUrl: _imageUrl,
        pointsWorth: int.parse(_pointsController.text.trim()),
      );

  GymClassUpdateData _buildUpdate() => GymClassUpdateData(
        className: _nameController.text.trim(),
        classDescription: _descriptionOrNull(),
        classTime: _formatTime(_classTime!),
        durationMinutes: int.parse(_durationController.text.trim()),
        recurringUnit: _safeUnit,
        recurringInterval: int.parse(_intervalController.text.trim()),
        sun: _day(0),
        mon: _day(1),
        tue: _day(2),
        wed: _day(3),
        thu: _day(4),
        fri: _day(5),
        sat: _day(6),
        sunInstructorId: _instructorFor(0),
        monInstructorId: _instructorFor(1),
        tueInstructorId: _instructorFor(2),
        wedInstructorId: _instructorFor(3),
        thuInstructorId: _instructorFor(4),
        friInstructorId: _instructorFor(5),
        satInstructorId: _instructorFor(6),
        startDate: _dateParam.format(_startDate!),
        endDate: _endDate == null ? null : _dateParam.format(_endDate!),
        maxCapacity: _capacityOrNull(),
        allowedPlanIds: _allowedPlanIds,
        imageUrl: _imageUrl,
        pointsWorth: int.parse(_pointsController.text.trim()),
      );

  // ---- mutation lifecycle --------------------------------------------------

  void _save() {
    final err = _validate();
    if (err != null) {
      setState(() => _inlineError = err);
      return;
    }
    final gymId = selectedGym.gymId ?? '';
    if (gymId.isEmpty) {
      setState(() => _inlineError = 'No active gym selected.');
      return;
    }
    final bloc = context.read<ScheduleBloc>();
    _action = _isEdit ? _ClassAction.update : _ClassAction.create;
    _beginMutation(bloc);
    if (_isEdit) {
      bloc.add(ScheduleClassUpdated(
        classId: widget.existing!.classId,
        data: _buildUpdate(),
      ));
    } else {
      bloc.add(ScheduleClassCreated(_buildCreate(gymId)));
    }
  }

  Future<void> _delete() async {
    final confirmed = await ConfirmationModal.show(
      context: context,
      title: 'Delete this class?',
      message: 'It is removed from the schedule. This cannot be undone here.',
      confirmLabel: 'Delete',
      confirmColor: DesignConstants.badRed,
    );
    if (!confirmed || !mounted) return;
    final bloc = context.read<ScheduleBloc>();
    _action = _ClassAction.delete;
    _beginMutation(bloc);
    bloc.add(ScheduleClassDeleted(widget.existing!.classId));
  }

  /// Open the cancel-a-date-range dialog for this class. Edit mode only — it
  /// shares the form's [ScheduleBloc], so a successful range cancel reloads the
  /// board the user returns to.
  void _openRangeCancel() {
    final existing = widget.existing;
    if (existing == null) return;
    ClassRangeCancelDialog.show(
      context: context,
      classId: existing.classId,
      className: existing.className,
    );
  }

  /// Open the batch staff check-in ("Update attendees") for this occurrence,
  /// sharing the form's [ScheduleBloc] so a successful run reloads the board.
  void _updateAttendees() {
    final existing = widget.existing;
    final date = widget.occurrenceDate;
    final gymId = selectedGym.gymId;
    if (existing == null || date == null || gymId == null) return;
    ClassBatchCheckInDialog.show(
      context: context,
      classId: existing.classId,
      gymId: gymId,
      className: existing.className,
      occurrenceDate: date,
    );
  }

  /// Cancel just this occurrence (after a confirm) through the board's bloc.
  /// On commit the form shows its success dialog and pops back to the board.
  Future<void> _cancelThisClass() async {
    final existing = widget.existing;
    final date = widget.occurrenceDate;
    if (existing == null || date == null) return;
    final confirmed = await ConfirmationModal.show(
      context: context,
      title: 'Cancel this class?',
      message: 'Only this date is cancelled — other dates are not affected.',
      confirmLabel: 'Cancel this class',
      confirmColor: DesignConstants.badRed,
    );
    if (!confirmed || !mounted) return;
    final bloc = context.read<ScheduleBloc>();
    _action = _ClassAction.cancelInstance;
    _beginMutation(bloc);
    bloc.add(ScheduleInstanceCancelled(classId: existing.classId, date: date));
  }

  void _beginMutation(ScheduleBloc bloc) {
    final state = bloc.state;
    _successBaseline =
        state is ScheduleLoaded ? state.actionSuccessCount : 0;
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

  /// A committed mutation ends in a success **dialog** (not a full-screen
  /// step); dismissing it pops the form back to the already-reloaded board.
  /// The spinner stays behind the dialog until the form pops.
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

  String get _successTitle {
    switch (_action) {
      case _ClassAction.create:
        return 'Class added';
      case _ClassAction.update:
        return 'Class updated';
      case _ClassAction.delete:
        return 'Class deleted';
      case _ClassAction.cancelInstance:
        return 'Class cancelled';
    }
  }

  String get _successMessage {
    switch (_action) {
      case _ClassAction.create:
        return 'Class added to the schedule.';
      case _ClassAction.update:
        return 'Class updated.';
      case _ClassAction.delete:
        return 'Class removed from the schedule.';
      case _ClassAction.cancelInstance:
        return 'This class is cancelled for that day.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      activeRoute: AppRoutes.schedule,
      child: BlocConsumer<ScheduleBloc, ScheduleState>(
        listener: _onState,
        builder: (context, state) {
          switch (_step) {
            case _Step.processing:
              return const _ProcessingView();
            case _Step.editing:
              final classes = state is ScheduleLoaded
                  ? state.classes
                  : const <GymClassResponse>[];
              return _form(InstructorOption.fromClasses(classes));
          }
        },
      ),
    );
  }

  Widget _form(List<InstructorOption> instructors) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(DesignConstants.paddingBig),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingBig,
        children: [
          _FormHeader(
            title: _isEdit ? 'Edit Class' : 'Add New Class',
            onBack: _close,
          ),
          if (_inlineError != null) ErrorMessage(message: _inlineError!),
          if (_hasOccurrence)
            ClassOccurrenceActions(
              occurrenceDate: widget.occurrenceDate!,
              cancellable: _occurrenceCancellable,
              isCancelled: widget.occurrenceCancelled,
              onUpdateAttendees: _updateAttendees,
              onCancelInstance: _cancelThisClass,
              roster: _rosterFor(),
            ),
          ClassDetailsSection(
            nameController: _nameController,
            descriptionController: _descriptionController,
            imageUrl: _imageUrl,
          ),
          ClassRewardsSection(
            pointsController: _pointsController,
            capacityController: _capacityController,
          ),
          ClassScheduleSection(
            classTime: _classTime,
            onTimeChanged: (t) => setState(() => _classTime = t),
            durationController: _durationController,
            recurringUnit: _recurringUnit,
            onUnitChanged: (u) =>
                setState(() => _recurringUnit = u ?? _recurringUnit),
            intervalController: _intervalController,
            startDate: _startDate,
            onStartChanged: (d) => setState(() => _startDate = d),
            endDate: _endDate,
            onEndChanged: (d) => setState(() => _endDate = d),
          ),
          ClassDaysSection(
            selectedDays: _selectedDays,
            onToggleDay: _toggleDay,
            instructorByDay: _instructorByDay,
            onInstructorChanged: (day, id) =>
                setState(() => _instructorByDay[day] = id),
            instructors: instructors,
          ),
          ClassFormActions(
            onCancel: _close,
            onSave: _save,
            onDelete: _isEdit ? _delete : null,
            onCancelRange: _isEdit ? _openRangeCancel : null,
          ),
        ],
      ),
    );
  }
}

class _FormHeader extends StatelessWidget {
  final String title;
  final VoidCallback onBack;

  const _FormHeader({required this.title, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingMedium,
      children: [
        InkWell(
          onTap: onBack,
          borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
          child: Padding(
            padding: const EdgeInsets.all(DesignConstants.spacingSmall),
            child: Icon(
              Symbols.arrow_back_sharp,
              color: DesignConstants.text2nd,
              weight: DesignConstants.iconWeight,
            ),
          ),
        ),
        Text(
          title,
          style: DesignConstants.h1.copyWith(color: DesignConstants.text2nd),
        ),
      ],
    );
  }
}

/// The in-flight step: a centered spinner while the write + reload run.
class _ProcessingView extends StatelessWidget {
  const _ProcessingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(DesignConstants.paddingBig),
        child: AppSpinner(),
      ),
    );
  }
}

