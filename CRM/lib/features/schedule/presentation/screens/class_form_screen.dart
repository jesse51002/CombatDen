import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/employees/data/models/employee.dart';
import 'package:crm/features/employees/data/repositories/employees_repository.dart';
import 'package:crm/features/schedule/bloc/schedule_bloc.dart';
import 'package:crm/features/schedule/bloc/schedule_event.dart';
import 'package:crm/features/schedule/bloc/schedule_state.dart';
import 'package:crm/features/schedule/data/class_time_format.dart';
import 'package:crm/features/schedule/data/models/class_slot.dart';
import 'package:crm/features/schedule/data/models/gym_class_create_request.dart';
import 'package:crm/features/schedule/data/models/gym_class_response.dart';
import 'package:crm/features/schedule/data/models/gym_class_update_request.dart';
import 'package:crm/features/schedule/data/models/instructor_option.dart';
import 'package:crm/features/schedule/data/models/recurring_unit.dart';
import 'package:crm/features/schedule/presentation/dialogs/class_range_cancel_dialog.dart';
import 'package:crm/features/schedule/presentation/dialogs/schedule_cancel_views.dart';
import 'package:crm/features/schedule/presentation/widgets/form/class_cancelled_ranges_section.dart';
import 'package:crm/features/schedule/presentation/widgets/form/class_days_section.dart';
import 'package:crm/features/schedule/presentation/widgets/form/class_details_section.dart';
import 'package:crm/features/schedule/presentation/widgets/form/class_form_actions.dart';
import 'package:crm/features/schedule/presentation/widgets/form/class_rewards_section.dart';
import 'package:crm/features/schedule/presentation/widgets/form/class_schedule_section.dart';
import 'package:crm/features/schedule/presentation/widgets/form/slot_draft.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_shell.dart';
import 'package:crm/shared/widgets/centered_processing_view.dart';
import 'package:crm/shared/widgets/confirmation_modal.dart';
import 'package:crm/shared/widgets/error_message.dart';

/// Day-index (0=Sun..6=Sat) -> the `weekday_slots` key name the backend
/// expects. Mirrors `WEEKDAY_SLOT_KEYS` in
/// `../FastApiBackend/src/classes/schema/classes_expander_schema.py`.
const List<String> _dayKeyNames = [
  'sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat',
];

/// Full weekday names for validation messages, index-aligned with
/// [_dayKeyNames].
const List<String> _dayFullNames = [
  'Sunday', 'Monday', 'Tuesday', 'Wednesday',
  'Thursday', 'Friday', 'Saturday',
];

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

  RecurringUnit _recurringUnit = RecurringUnit.weekly;
  DateTime? _startDate;
  DateTime? _endDate;

  /// Day index (0=Sun..6=Sat) -> its slot drafts (weekly), PLUS the
  /// [kAllDaysSlotKey] bucket (daily/monthly) — both may be populated at
  /// once so switching [_recurringUnit] never loses the other mode's
  /// already-entered slots; only the relevant half is validated/submitted.
  Map<int, List<SlotDraft>> _daySlots = {};
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

  /// The gym's staff roster, side-read once so the per-slot instructor picker
  /// lists real employees (not only instructors already assigned on a class).
  /// Best-effort: a failure leaves it empty and the picker falls back to the
  /// from-classes instructors.
  List<Employee> _employees = const [];

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    if (c != null) _prefill(c);
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

  void _prefill(GymClassResponse c) {
    _nameController.text = c.className;
    _descriptionController.text = c.classDescription ?? '';
    _pointsController.text = c.pointsWorth.toString();
    _capacityEnabled = c.maxCapacity != null;
    _capacityController.text = c.maxCapacity?.toString() ?? '';
    _durationController.text = c.durationMinutes.toString();
    _intervalController.text = c.recurringInterval.toString();
    _recurringUnit = c.recurringUnit == RecurringUnit.unknown
        ? RecurringUnit.weekly
        : c.recurringUnit;
    _startDate = _dateOnly(c.startDate);
    _endDate = c.endDate == null ? null : _dateOnly(c.endDate!);
    _daySlots = _draftsFromWeekdaySlots(c.weekdaySlots);
    _imageUrl = c.imageUrl;
    _allowedPlanIds = c.allowedPlanIds;
  }

  /// Maps a backend `weekday_slots` response shape onto the form's draft map
  /// — `"all"` -> [kAllDaysSlotKey], `sun`..`sat` -> 0..6.
  static Map<int, List<SlotDraft>> _draftsFromWeekdaySlots(
    Map<String, List<ClassSlot>> weekdaySlots,
  ) {
    final result = <int, List<SlotDraft>>{};
    for (final entry in weekdaySlots.entries) {
      final drafts = entry.value
          .map((s) => SlotDraft(
                time: parseHmsTime(s.time),
                instructorId: s.instructorId,
              ))
          .toList();
      if (entry.key == 'all') {
        result[kAllDaysSlotKey] = drafts;
        continue;
      }
      final idx = _dayKeyNames.indexOf(entry.key);
      if (idx != -1) result[idx] = drafts;
    }
    return result;
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

  /// Toggling a day ON adds it with one empty slot draft; OFF removes it
  /// (and every slot it held).
  void _toggleDay(int day) {
    setState(() {
      if (_daySlots.containsKey(day)) {
        _daySlots.remove(day);
      } else {
        _daySlots[day] = [SlotDraft()];
      }
    });
  }

  void _addSlot(int day) {
    setState(() => _daySlots.putIfAbsent(day, () => []).add(SlotDraft()));
  }

  void _removeSlot(int day, int index) {
    setState(() => _daySlots[day]?.removeAt(index));
  }

  void _onSlotTimeChanged(int day, int index, TimeOfDay time) {
    setState(() => _daySlots[day]![index].time = time);
  }

  void _onSlotInstructorChanged(int day, int index, String? instructorId) {
    setState(() => _daySlots[day]![index].instructorId = instructorId);
  }

  /// Switching recurrence unit doesn't clear the other mode's slots (see
  /// [_daySlots]) — but the FIRST time a daily/monthly unit is selected and
  /// its `"all"` bucket is still empty, seed one blank slot so the "Times"
  /// section isn't just an empty "Add time" prompt (mirrors [_toggleDay]'s
  /// convenience for a weekly day).
  void _onUnitChanged(RecurringUnit? unit) {
    if (unit == null) return;
    setState(() {
      _recurringUnit = unit;
      if (unit != RecurringUnit.weekly) {
        final all = _daySlots[kAllDaysSlotKey];
        if (all == null || all.isEmpty) {
          _daySlots[kAllDaysSlotKey] = [SlotDraft()];
        }
      }
    });
  }

  void _close() => Navigator.of(context).pop();

  // ---- form-model <-> request conversions ---------------------------------

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// The `weekday_slots` shape this form would currently submit — sun..sat
  /// keys (weekly) or the reserved "all" key (daily/monthly), each list only
  /// the slots with a picked time. Shared by [_buildCreate]/[_buildUpdate]
  /// and [_scheduleChanged]'s diff.
  Map<String, List<ClassSlot>> _weekdaySlotsForRequest() {
    final result = <String, List<ClassSlot>>{};
    if (_safeUnit == RecurringUnit.weekly) {
      for (final entry in _daySlots.entries) {
        if (entry.key < 0 || entry.key > 6) continue;
        final slots = _slotsForRequest(entry.value);
        if (slots.isNotEmpty) result[_dayKeyNames[entry.key]] = slots;
      }
    } else {
      final slots = _slotsForRequest(_daySlots[kAllDaysSlotKey] ?? const []);
      if (slots.isNotEmpty) result['all'] = slots;
    }
    return result;
  }

  static List<ClassSlot> _slotsForRequest(List<SlotDraft> drafts) => [
        for (final d in drafts)
          if (d.time != null)
            ClassSlot(
              time: formatTimeOfDayHms(d.time!),
              instructorId: d.instructorId,
            ),
      ];

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
    if (_startDate == null) return 'Pick a start date.';
    final duration = int.tryParse(_durationController.text.trim());
    if (duration == null || duration <= 0) return 'Enter a duration above 0.';
    final interval = int.tryParse(_intervalController.text.trim());
    if (interval == null || interval <= 0) return 'Enter an interval above 0.';
    final points = int.tryParse(_pointsController.text.trim());
    if (points == null || points <= 0) return 'Enter points above 0.';
    return _validateSchedule();
  }

  /// Every active day (weekly) or the single "all" bucket (daily/monthly)
  /// needs >=1 slot with a picked time, and no two slots on the same day may
  /// share a time — the backend 422s on either violation, but a clear inline
  /// error beats waiting for that round trip.
  String? _validateSchedule() {
    if (_safeUnit != RecurringUnit.weekly) {
      return _validateSlots(_daySlots[kAllDaysSlotKey] ?? const [], 'Times');
    }
    final activeDays = _daySlots.keys.where((k) => k >= 0 && k <= 6).toList()
      ..sort();
    if (activeDays.isEmpty) return 'Select at least one day.';
    for (final day in activeDays) {
      final err =
          _validateSlots(_daySlots[day] ?? const [], _dayFullNames[day]);
      if (err != null) return err;
    }
    return null;
  }

  static String? _validateSlots(List<SlotDraft> drafts, String label) {
    final times = [
      for (final d in drafts)
        if (d.time != null) formatTimeOfDayHms(d.time!),
    ];
    if (times.isEmpty) return '$label needs at least one time.';
    if (times.toSet().length != times.length) {
      return '$label has two slots at the same time.';
    }
    return null;
  }

  GymClassCreateRequest _buildCreate(String gymId) => GymClassCreateRequest(
        gymId: gymId,
        className: _nameController.text.trim(),
        classDescription: _descriptionOrNull(),
        durationMinutes: int.parse(_durationController.text.trim()),
        recurringUnit: _safeUnit,
        recurringInterval: int.parse(_intervalController.text.trim()),
        weekdaySlots: _weekdaySlotsForRequest(),
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
          durationMinutes: int.parse(_durationController.text.trim()),
          recurringUnit: _safeUnit,
          recurringInterval: int.parse(_intervalController.text.trim()),
          weekdaySlots: _weekdaySlotsForRequest(),
          startDate: _dateParam.format(_startDate!),
          endDate: _endDate == null ? null : _dateParam.format(_endDate!),
        ),
      );

  /// Whether any schedule-SHAPE field differs from the loaded class —
  /// duration, recurrence unit/interval, the weekday_slots map (day-set,
  /// times, per-slot instructors), start/end date. Identity-only edits
  /// (name, description, capacity, points, image, plans) return false, so
  /// they submit without the going-forward warning. Only meaningful after
  /// [_validate] passes (the numeric parses assume valid fields).
  bool _scheduleChanged() {
    final c = widget.existing;
    if (c == null) return false;
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
    if (!_isSameDay(_startDate!, _dateOnly(c.startDate))) return true;
    final existingEnd = c.endDate == null ? null : _dateOnly(c.endDate!);
    final end = _endDate;
    if ((end == null) != (existingEnd == null)) return true;
    if (end != null && !_isSameDay(end, existingEnd!)) return true;
    return !_weekdaySlotsEqual(_weekdaySlotsForRequest(), c.weekdaySlots);
  }

  /// Order-insensitive per-day comparison (the backend always returns
  /// sorted-by-time lists; the form's own build may not be) — compares only
  /// time + instructor, since a request slot never carries `instructorName`.
  static bool _weekdaySlotsEqual(
    Map<String, List<ClassSlot>> a,
    Map<String, List<ClassSlot>> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final bSlots = b[entry.key];
      if (bSlots == null) return false;
      final aSorted = [...entry.value]
        ..sort((x, y) => x.time.compareTo(y.time));
      final bSorted = [...bSlots]..sort((x, y) => x.time.compareTo(y.time));
      if (aSorted.length != bSorted.length) return false;
      for (var i = 0; i < aSorted.length; i++) {
        if (aSorted[i].time != bSorted[i].time) return false;
        if (aSorted[i].instructorId != bSorted[i].instructorId) return false;
      }
    }
    return true;
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
              return _form(InstructorOption.merged(_employees, classes));
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
            onImageChanged: (url) => setState(() => _imageUrl = url),
          ),
          ClassRewardsSection(
            pointsController: _pointsController,
            capacityController: _capacityController,
            capacityEnabled: _capacityEnabled,
            onCapacityEnabledChanged: (v) =>
                setState(() => _capacityEnabled = v),
          ),
          ClassScheduleSection(
            durationController: _durationController,
            recurringUnit: _recurringUnit,
            onUnitChanged: _onUnitChanged,
            intervalController: _intervalController,
            startDate: _startDate,
            onStartChanged: (d) => setState(() => _startDate = d),
            endDate: _endDate,
            onEndChanged: (d) => setState(() => _endDate = d),
          ),
          ClassDaysSection(
            recurringUnit: _safeUnit,
            daySlots: _daySlots,
            onToggleDay: _toggleDay,
            onAddSlot: _addSlot,
            onRemoveSlot: _removeSlot,
            onSlotTimeChanged: _onSlotTimeChanged,
            onSlotInstructorChanged: _onSlotInstructorChanged,
            instructors: instructors,
          ),
          if (_isEdit)
            ClassCancelledRangesSection(
              classId: widget.existing!.classId,
              className: widget.existing!.className,
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

