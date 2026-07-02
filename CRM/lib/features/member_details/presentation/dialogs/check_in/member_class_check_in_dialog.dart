import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/check_in/presentation/widgets/check_in_dialog_actions.dart';
import 'package:crm/features/check_in/presentation/widgets/check_in_processing_view.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/presentation/dialogs/check_in/check_in_class_group.dart';
import 'package:crm/features/member_details/presentation/dialogs/check_in/check_in_class_picker.dart';
import 'package:crm/features/member_details/presentation/dialogs/check_in/check_in_reserve_selection.dart';
import 'package:crm/features/member_details/presentation/dialogs/check_in/check_in_section.dart';
import 'package:crm/features/member_details/presentation/dialogs/check_in/member_check_in_pick_body.dart';
import 'package:crm/features/member_details/presentation/dialogs/check_in/member_check_in_result_view.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/view_switcher.dart';

enum _Phase { pick, processing, result }

/// The pick phase's own page stack for the **Check in** view: the emphasized
/// current-classes list, then (via "Check into a past class") an
/// identity-level class picker, then that class's past occurrences.
enum _CheckInStep { current, pastClasses, pastOccurrences }

/// The pick phase's own page stack for the **Reserve** view:
/// identity-level class cards first, then the picked class's upcoming
/// occurrences.
enum _ReserveStep { classes, occurrences }

/// "Check in / Reserve" for the viewed member: a top-level [ViewSwitcher]
/// between **Check in** and **Reserve**, each owning its own in-dialog step
/// (see [_CheckInStep] / [_ReserveStep]) so a class is picked at the
/// IDENTITY level (an image card, like the schedule board's `ClassCard`)
/// before its date/time.
///
/// **Check in**: step 1 is the existing occurrence-level list for CURRENT
/// classes (in session or starting within the next 2h) plus a "Check into a
/// past class" action; that opens step 2, the identity-level class picker
/// over already-ended occurrences, then step 3, that class's past
/// occurrences (most recent first) for a retroactive check-in.
///
/// **Reserve**: step 1 is the identity-level class picker over any class
/// with an upcoming occurrence; step 2 is that class's upcoming occurrences
/// (soonest first).
///
/// A class starting within the next 2h INTENTIONALLY appears in both the
/// Check-in view's current list AND the Reserve view's class picker — only a
/// class already in session is Check-in-only. The split/sort logic lives in
/// [MemberCheckInPickBody]; each view tracks its own picked occurrence
/// ([_checkInSelected] / [_reserveSelected]) so the mutation this dialog
/// submits always matches the active view.
///
/// This is a PICK-FLOW redesign only — the terminal mutations/results are
/// untouched: **Check in** dispatches [MemberCheckInRequested] (warn-first,
/// with a "Check in anyway" override on a gate warning); **Reserve**
/// dispatches [MemberReserveRequested] (idempotent repeat, "Class is full"
/// on a full occurrence, no override).
class MemberClassCheckInDialog extends StatefulWidget {
  final String gymId;

  const MemberClassCheckInDialog({super.key, required this.gymId});

  static Future<void> show({
    required BuildContext context,
    required String gymId,
  }) {
    final bloc = context.read<MemberDetailBloc>();
    final schedule = context.read<ScheduleRepository>();
    return showDialog<void>(
      context: context,
      builder: (_) => RepositoryProvider<ScheduleRepository>.value(
        value: schedule,
        child: BlocProvider<MemberDetailBloc>.value(
          value: bloc,
          child: MemberClassCheckInDialog(gymId: gymId),
        ),
      ),
    );
  }

  @override
  State<MemberClassCheckInDialog> createState() =>
      _MemberClassCheckInDialogState();
}

class _MemberClassCheckInDialogState extends State<MemberClassCheckInDialog> {
  _Phase _phase = _Phase.pick;

  /// 0 = Check in, 1 = Reserve — the top-level [ViewSwitcher] index.
  int _view = 0;

  _CheckInStep _checkInStep = _CheckInStep.current;
  _ReserveStep _reserveStep = _ReserveStep.classes;

  /// The class picked in the Check-in view's identity picker (step 2) —
  /// drives which class's occurrences step 3 filters to.
  String? _checkInPastClassId;

  /// The class picked in the Reserve view's identity picker (step 1).
  String? _reserveClassId;

  /// Each view's own picked occurrence, kept independent so switching the
  /// top-level view never carries a stale pick (and its action) into the
  /// other view.
  EffectiveClassInstance? _checkInSelected;
  EffectiveClassInstance? _reserveSelected;

  /// The `ignoreWarnings` value of the last dispatched check-in, so "Try
  /// again" (on an unexpected error) retries with the same intent as the
  /// attempt that failed — including a failed "Check in anyway" retry.
  /// Unused for a reserve retry (reserve has no override).
  bool _lastIgnoreWarnings = false;

  /// The active view's pick, wrapped with the action it drives. Computed
  /// (not stored) so it always matches [_view] — see [_checkInSelected] /
  /// [_reserveSelected].
  CheckInReserveSelection? get _selected {
    if (_view == 0) {
      final i = _checkInSelected;
      return i == null
          ? null
          : CheckInReserveSelection(
              instance: i,
              action: CheckInReserveAction.checkIn,
            );
    }
    final i = _reserveSelected;
    return i == null
        ? null
        : CheckInReserveSelection(
            instance: i,
            action: CheckInReserveAction.reserve,
          );
  }

  bool get _isReserve => _selected?.action == CheckInReserveAction.reserve;

  @override
  void initState() {
    super.initState();
    context.read<MemberDetailBloc>()
      ..add(const MemberCheckInCleared())
      ..add(const MemberReserveCleared());
  }

  void _submit({bool ignoreWarnings = false}) {
    final selected = _selected;
    if (selected == null) return;
    setState(() => _phase = _Phase.processing);
    final bloc = context.read<MemberDetailBloc>();
    if (selected.action == CheckInReserveAction.reserve) {
      bloc.add(
        MemberReserveRequested(
          classId: selected.instance.classId,
          occurrenceDate: selected.instance.originalDate,
        ),
      );
      return;
    }
    _lastIgnoreWarnings = ignoreWarnings;
    bloc.add(
      MemberCheckInRequested(
        classId: selected.instance.classId,
        occurrenceDate: selected.instance.originalDate,
        ignoreWarnings: ignoreWarnings,
      ),
    );
  }

  /// A settled check-in/reserve (result or error) is the terminal step —
  /// watches whichever channel the current selection's action drives.
  void _onState(BuildContext context, MemberDetailState state) {
    if (_phase != _Phase.processing) return;
    if (state is! MemberDetailLoaded) return;
    if (_isReserve) {
      if (state.isReserving) return;
      if (state.reserveResult != null || state.reserveError != null) {
        setState(() => _phase = _Phase.result);
      }
      return;
    }
    if (state.isCheckingIn) return;
    if (state.checkInResult != null || state.checkInError != null) {
      setState(() => _phase = _Phase.result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<MemberDetailBloc, MemberDetailState>(
      listener: _onState,
      builder: (context, state) {
        final loaded = state is MemberDetailLoaded ? state : null;
        return AppDialog(
          title: 'Check in / Reserve',
          maxWidth: DesignConstants.dialogContentMaxWidth,
          body: _body(loaded),
          actions: _actions(loaded),
        );
      },
    );
  }

  Widget _body(MemberDetailLoaded? loaded) {
    switch (_phase) {
      case _Phase.processing:
        return const CheckInProcessingView();
      case _Phase.result:
        return MemberCheckInResultView(
          action: _selected?.action ?? CheckInReserveAction.checkIn,
          instanceName: _selected?.instance.className ?? 'the class',
          checkInResult: _isReserve ? null : loaded?.checkInResult,
          reserveResult: _isReserve ? loaded?.reserveResult : null,
          error: _isReserve ? loaded?.reserveError : loaded?.checkInError,
        );
      case _Phase.pick:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingBig,
          children: [
            ViewSwitcher(
              labels: const ['Check in', 'Reserve'],
              selectedIndex: _view,
              onSelected: (i) => setState(() => _view = i),
            ),
            MemberCheckInPickBody(
              gymId: widget.gymId,
              builder: (context, checkIn, past, reserve) => _view == 0
                  ? _checkInBody(checkIn, past)
                  : _reserveBody(reserve),
            ),
          ],
        );
    }
  }

  Widget _checkInBody(
    List<EffectiveClassInstance> checkIn,
    List<EffectiveClassInstance> past,
  ) {
    switch (_checkInStep) {
      case _CheckInStep.current:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingBig,
          children: [
            CheckInSection(
              title: 'Check in',
              action: CheckInReserveAction.checkIn,
              instances: checkIn,
              selectedKey: _checkInSelectedKey,
              onSelect: (sel) =>
                  setState(() => _checkInSelected = sel.instance),
              emptyLabel: 'No classes open for check-in right now.',
            ),
            if (past.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: AppOutlineButton(
                  text: 'Check into a past class',
                  borderRadius: DesignConstants.radiusSmall,
                  onPressed: () =>
                      setState(() => _checkInStep = _CheckInStep.pastClasses),
                ),
              ),
          ],
        );
      case _CheckInStep.pastClasses:
        return CheckInClassPicker(
          groups: groupInstancesByClass(past),
          hintPrefix: 'Last',
          emptyLabel: 'No past classes in the last 30 days.',
          onSelect: (classId) => setState(() {
            _checkInPastClassId = classId;
            _checkInStep = _CheckInStep.pastOccurrences;
          }),
        );
      case _CheckInStep.pastOccurrences:
        final occurrences =
            past.where((i) => i.classId == _checkInPastClassId).toList();
        return CheckInSection(
          title: occurrences.isNotEmpty
              ? occurrences.first.className
              : 'Past occurrences',
          action: CheckInReserveAction.checkIn,
          instances: occurrences,
          selectedKey: _checkInSelectedKey,
          onSelect: (sel) => setState(() => _checkInSelected = sel.instance),
        );
    }
  }

  Widget _reserveBody(List<EffectiveClassInstance> reserve) {
    switch (_reserveStep) {
      case _ReserveStep.classes:
        return CheckInClassPicker(
          groups: groupInstancesByClass(reserve),
          hintPrefix: 'Next',
          emptyLabel: 'No classes have upcoming occurrences to reserve.',
          onSelect: (classId) => setState(() {
            _reserveClassId = classId;
            _reserveStep = _ReserveStep.occurrences;
          }),
        );
      case _ReserveStep.occurrences:
        final occurrences =
            reserve.where((i) => i.classId == _reserveClassId).toList();
        return CheckInSection(
          title: occurrences.isNotEmpty
              ? occurrences.first.className
              : 'Occurrences',
          action: CheckInReserveAction.reserve,
          instances: occurrences,
          selectedKey: _reserveSelectedKey,
          onSelect: (sel) => setState(() => _reserveSelected = sel.instance),
        );
    }
  }

  String? get _checkInSelectedKey => _checkInSelected == null
      ? null
      : CheckInSection.keyFor(CheckInReserveAction.checkIn, _checkInSelected!);

  String? get _reserveSelectedKey => _reserveSelected == null
      ? null
      : CheckInSection.keyFor(
          CheckInReserveAction.reserve,
          _reserveSelected!,
        );

  Widget? _actions(MemberDetailLoaded? loaded) {
    switch (_phase) {
      case _Phase.processing:
        return null;
      case _Phase.result:
        if (_isReserve) {
          if (loaded?.reserveError != null) {
            return checkInChoiceActions(
              primaryLabel: 'Try again',
              onPrimary: () => _submit(),
              dismissLabel: 'Close',
            );
          }
          return checkInDoneActions(context);
        }
        if (loaded?.checkInError != null) {
          return checkInChoiceActions(
            primaryLabel: 'Try again',
            onPrimary: () => _submit(ignoreWarnings: _lastIgnoreWarnings),
            dismissLabel: 'Close',
          );
        }
        if (loaded?.checkInResult?.requiresConfirmation ?? false) {
          return checkInChoiceActions(
            primaryLabel: 'Check in anyway',
            onPrimary: () => _submit(ignoreWarnings: true),
            dismissLabel: 'Close',
          );
        }
        return checkInDoneActions(context);
      case _Phase.pick:
        return _pickActions();
    }
  }

  Widget _pickActions() {
    if (_view == 0) {
      switch (_checkInStep) {
        case _CheckInStep.current:
          return checkInChoiceActions(
            primaryLabel: 'Check in',
            onPrimary: _checkInSelected == null ? null : () => _submit(),
            dismissLabel: 'Cancel',
          );
        case _CheckInStep.pastClasses:
          return AppDialogActions(
            primaryLabel: 'Select a class',
            secondaryLabel: 'Back',
            secondaryOnPressed: () =>
                setState(() => _checkInStep = _CheckInStep.current),
          );
        case _CheckInStep.pastOccurrences:
          return AppDialogActions(
            primaryLabel: 'Check in',
            primaryOnPressed:
                _checkInSelected == null ? null : () => _submit(),
            secondaryLabel: 'Back',
            secondaryOnPressed: () =>
                setState(() => _checkInStep = _CheckInStep.pastClasses),
          );
      }
    }
    switch (_reserveStep) {
      case _ReserveStep.classes:
        return const AppDialogActions(
          primaryLabel: 'Select a class',
          secondaryLabel: 'Cancel',
        );
      case _ReserveStep.occurrences:
        return AppDialogActions(
          primaryLabel: 'Reserve',
          primaryOnPressed: _reserveSelected == null ? null : () => _submit(),
          secondaryLabel: 'Back',
          secondaryOnPressed: () =>
              setState(() => _reserveStep = _ReserveStep.classes),
        );
    }
  }
}
