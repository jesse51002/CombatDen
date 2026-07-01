import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/features/check_in/presentation/widgets/check_in_dialog_actions.dart';
import 'package:crm/features/check_in/presentation/widgets/check_in_processing_view.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/presentation/dialogs/check_in/check_in_reserve_selection.dart';
import 'package:crm/features/member_details/presentation/dialogs/check_in/check_in_section.dart';
import 'package:crm/features/member_details/presentation/dialogs/check_in/member_check_in_pick_body.dart';
import 'package:crm/features/member_details/presentation/dialogs/check_in/member_check_in_result_view.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';

enum _Phase { pick, processing, result }

/// "Check in / Reserve" for the viewed member: a **Check in** section
/// (emphasized — occurrences in session or starting within the next 2h,
/// soonest first), a **"Show past classes"** toggle revealing already-ended
/// occurrences for a retroactive check-in (most recent first), and a
/// **Reserve** section (any not-yet-started occurrence — soonest first;
/// intentionally overlaps Check-in for a class starting within the next 2h).
/// The split/sort logic lives in [MemberCheckInPickBody]; each pick carries
/// its own [CheckInReserveAction] since the same occurrence can appear under
/// both actions.
///
/// **Check in**: dispatches [MemberCheckInRequested]. A clean check-in
/// records and the result names the class + points (with any non-blocking
/// warnings); one that hits a gate warning is held for confirmation
/// (`requiresConfirmation`, nothing written) and the result step offers
/// "Check in anyway", which re-dispatches the same check-in with
/// `ignoreWarnings: true`.
///
/// **Reserve**: dispatches [MemberReserveRequested], which reuses the
/// schedule feature's sign-up wiring (`ScheduleRepository.signUp`) for this
/// one member/occurrence. A clean reserve records ("Reserved for …"), a
/// repeat is idempotent ("Already reserved"), and a full class surfaces its
/// "Class is full" error — there is no override for a reserve failure
/// (mirrors the schedule feature's own "Sign up members" dialog).
///
/// Reads occurrences via the member-detail screen's [ScheduleRepository] and
/// runs both actions through the [MemberDetailBloc]'s dedicated channels.
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

class _MemberClassCheckInDialogState
    extends State<MemberClassCheckInDialog> {
  _Phase _phase = _Phase.pick;
  CheckInReserveSelection? _selected;

  /// The `ignoreWarnings` value of the last dispatched check-in, so "Try
  /// again" (on an unexpected error) retries with the same intent as the
  /// attempt that failed — including a failed "Check in anyway" retry.
  /// Unused for a reserve retry (reserve has no override).
  bool _lastIgnoreWarnings = false;

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
          occurrenceDate: selected.instance.classDate,
        ),
      );
      return;
    }
    _lastIgnoreWarnings = ignoreWarnings;
    bloc.add(
      MemberCheckInRequested(
        classId: selected.instance.classId,
        occurrenceDate: selected.instance.classDate,
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
        return MemberCheckInPickBody(
          gymId: widget.gymId,
          selectedKey: _selected == null
              ? null
              : CheckInSection.keyFor(_selected!.action, _selected!.instance),
          onSelect: (sel) => setState(() => _selected = sel),
        );
    }
  }

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
        return checkInChoiceActions(
          primaryLabel: _isReserve ? 'Reserve' : 'Check in',
          onPrimary: _selected == null ? null : () => _submit(),
          dismissLabel: 'Cancel',
        );
    }
  }
}
