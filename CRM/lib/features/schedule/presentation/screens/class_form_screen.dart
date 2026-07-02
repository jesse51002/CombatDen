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
import 'package:crm/features/schedule/data/class_time_format.dart';
import 'package:crm/features/schedule/data/models/gym_class_create_request.dart';
import 'package:crm/features/schedule/data/models/gym_class_response.dart';
import 'package:crm/features/schedule/data/models/gym_class_update_request.dart';
import 'package:crm/features/schedule/data/models/instructor_option.dart';
import 'package:crm/features/schedule/data/models/recurring_unit.dart';
import 'package:crm/features/schedule/presentation/dialogs/class_range_cancel_dialog.dart';
import 'package:crm/features/schedule/presentation/dialogs/schedule_cancel_views.dart';
import 'package:crm/features/schedule/presentation/widgets/form/class_days_section.dart';
import 'package:crm/features/schedule/presentation/widgets/form/class_details_section.dart';
import 'package:crm/features/schedule/presentation/widgets/form/class_form_actions.dart';
import 'package:crm/features/schedule/presentation/widgets/form/class_rewards_section.dart';
import 'package:crm/features/schedule/presentation/widgets/form/class_schedule_section.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_shell.dart';
import 'package:crm/shared/widgets/centered_processing_view.dart';
import 'package:crm/shared/widgets/confirmation_modal.dart';
import 'package:crm/shared/widgets/error_message.dart';

/// Which mutation the form is running (drives the success copy).
enum _ClassAction { create, update, delete }

/// The form's run state: edit the fields, or processing (a spinner) while a
/// mutation + board reload run. A committed mutation surfaces a success
/// **dialog** over the spinner, then pops the form; a failure returns to
/// editing with an inline error (the Save button retries).
enum _Step { editing, processing }

/// Full-page Add/Edit Class **definition** form, wired live to the FastAPI
/// `classes` domain through the board's shared [ScheduleBloc] (provided by the
/// caller via `BlocProvider.value`). Saving dispatches `ScheduleClassCreated` /
/// `ScheduleClassUpdated`; deleting dispatches `ScheduleClassDeleted`. The
/// bloc reloads the board on success, so dismissing the confirmation drops the
/// user back onto an already-fresh schedule.
///
/// Pass [existing] (the real [GymClassResponse] from the board) to edit; omit
/// it to create. This screen edits the **recurring definition only** — name,
/// description, recurrence, per-weekday instructors, capacity, points, image,
/// start/end date, and (edit mode) "Cancel a date range" / delete. A single
/// occurrence's overrides / attendance / cancel-this-day live on the separate
/// `class_occurrence_screen.dart`, opened from the chooser dialog's "This
/// occurrence" option instead.
class ClassFormScreen extends StatefulWidget {
  final GymClassResponse? existing;

  const ClassFormScreen({super.key, this.existing});

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
  bool _capacityEnabled = false;

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
    _capacityEnabled = c.maxCapacity != null;
    _capacityController.text = c.maxCapacity?.toString() ?? '';
    _durationController.text = c.durationMinutes.toString();
    _intervalController.text = c.recurringInterval.toString();
    _classTime = parseHmsTime(c.classTime);
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

  bool _day(int i) => _selectedDays.contains(i);

  /// The instructor for day [i] — only when that day is active.
  String? _instructorFor(int i) =>
      _selectedDays.contains(i) ? _instructorByDay[i] : null;

  String? _descriptionOrNull() {
    final t = _descriptionController.text.trim();
    return t.isEmpty ? null : t;
  }

  int? _capacityOrNull() {
    if (!_capacityEnabled) return null;
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
        classTime: formatTimeOfDayHms(_classTime!),
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

  /// Builds the split update body. The form doesn't track which half of the
  /// class actually changed, so it sends BOTH the identity fields and the
  /// complete schedule shape every time — safe by contract (a schedule
  /// deep-equal to the current version is a backend no-op).
  GymClassUpdateRequest _buildUpdate() => GymClassUpdateRequest(
        identity: GymClassIdentityUpdateData(
          className: _nameController.text.trim(),
          classDescription: _descriptionOrNull(),
          maxCapacity: _capacityOrNull(),
          allowedPlanIds: _allowedPlanIds,
          imageUrl: _imageUrl,
          pointsWorth: int.parse(_pointsController.text.trim()),
        ),
        schedule: GymClassScheduleFields(
          classTime: formatTimeOfDayHms(_classTime!),
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
        ),
      );

  /// Whether any schedule-SHAPE field differs from the loaded class — time,
  /// duration, recurrence unit/interval, weekday flags, per-day instructors,
  /// start/end date. Identity-only edits (name, description, capacity,
  /// points, image, plans) return false, so they submit without the
  /// going-forward warning. Only meaningful after [_validate] passes (the
  /// numeric parses assume valid fields).
  bool _scheduleChanged() {
    final c = widget.existing;
    if (c == null) return false;
    if (_classTime != parseHmsTime(c.classTime)) return true;
    if (int.parse(_durationController.text.trim()) != c.durationMinutes) {
      return true;
    }
    final existingUnit = c.recurringUnit == RecurringUnit.unknown
        ? RecurringUnit.weekly
        : c.recurringUnit;
    if (_safeUnit != existingUnit) return true;
    if (int.parse(_intervalController.text.trim()) != c.recurringInterval) {
      return true;
    }
    final existingDays = [c.sun, c.mon, c.tue, c.wed, c.thu, c.fri, c.sat];
    final existingInstructors = [
      c.sunInstructorId,
      c.monInstructorId,
      c.tueInstructorId,
      c.wedInstructorId,
      c.thuInstructorId,
      c.friInstructorId,
      c.satInstructorId,
    ];
    for (var i = 0; i < 7; i++) {
      if (_day(i) != existingDays[i]) return true;
      // Compare what would be SENT (null for an inactive day) against the
      // class's own value under the same normalization.
      final existing = existingDays[i] ? existingInstructors[i] : null;
      if (_instructorFor(i) != existing) return true;
    }
    if (!_isSameDay(_startDate!, _dateOnly(c.startDate))) return true;
    final existingEnd = c.endDate == null ? null : _dateOnly(c.endDate!);
    final end = _endDate;
    if ((end == null) != (existingEnd == null)) return true;
    if (end != null && !_isSameDay(end, existingEnd!)) return true;
    return false;
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // ---- mutation lifecycle --------------------------------------------------

  Future<void> _save() async {
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
    // A schedule-shape change (edit mode) clears reservations + early
    // check-ins on upcoming dates whose slot no longer matches the new time
    // exactly — confirm before submitting. Identity-only edits skip this.
    if (_isEdit && _scheduleChanged()) {
      final confirmed = await ConfirmationModal.show(
        context: context,
        title: 'Change the schedule?',
        message: 'Schedule changes apply going forward: upcoming dates that '
            'no longer match the new time lose their reservations and early '
            'check-ins (points reversed). Past classes are unaffected.',
        confirmLabel: 'Save changes',
      );
      if (!confirmed || !mounted) return;
    }
    final bloc = context.read<ScheduleBloc>();
    _action = _isEdit ? _ClassAction.update : _ClassAction.create;
    _beginMutation(bloc);
    if (_isEdit) {
      bloc.add(ScheduleClassUpdated(
        classId: widget.existing!.classId,
        request: _buildUpdate(),
      ));
    } else {
      bloc.add(ScheduleClassCreated(_buildCreate(gymId)));
    }
  }

  Future<void> _delete() async {
    final confirmed = await ConfirmationModal.show(
      context: context,
      title: 'Delete this class?',
      message: 'Upcoming reservations and early check-ins are cleared '
          '(points reversed). Past attendance history is kept. '
          'This can\'t be undone.',
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
              return const CenteredProcessingView();
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
          ClassDetailsSection(
            nameController: _nameController,
            descriptionController: _descriptionController,
            imageUrl: _imageUrl,
          ),
          ClassRewardsSection(
            pointsController: _pointsController,
            capacityController: _capacityController,
            capacityEnabled: _capacityEnabled,
            onCapacityEnabledChanged: (v) =>
                setState(() => _capacityEnabled = v),
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

