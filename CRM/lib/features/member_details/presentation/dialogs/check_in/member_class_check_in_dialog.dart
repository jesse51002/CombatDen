import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/features/check_in/presentation/widgets/check_in_dialog_actions.dart';
import 'package:crm/features/check_in/presentation/widgets/check_in_processing_view.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/presentation/dialogs/check_in/check_in_section.dart';
import 'package:crm/features/member_details/presentation/dialogs/check_in/member_check_in_pick_body.dart';
import 'package:crm/features/member_details/presentation/dialogs/check_in/member_check_in_result_view.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';

enum _Phase { pick, processing, result }

/// Two-section staff check-in for the viewed member: TODAY's classes (Active,
/// emphasized) and the LAST 7 DAYS (Past). Pick one → "Check in" dispatches
/// [MemberCheckInRequested]; staff always records, so the result names the
/// class + points and surfaces any non-blocking warnings (no "check in anyway"
/// retry). Reads occurrences via the member-detail screen's [ScheduleRepository]
/// and runs the check-in through the [MemberDetailBloc]'s dedicated channel.
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
  EffectiveClassInstance? _selected;

  @override
  void initState() {
    super.initState();
    context.read<MemberDetailBloc>().add(const MemberCheckInCleared());
  }

  void _submit() {
    final selected = _selected;
    if (selected == null) return;
    setState(() => _phase = _Phase.processing);
    context.read<MemberDetailBloc>().add(
          MemberCheckInRequested(
            classId: selected.classId,
            occurrenceDate: selected.classDate,
          ),
        );
  }

  /// A settled check-in (result or error) is the terminal step.
  void _onState(BuildContext context, MemberDetailState state) {
    if (_phase != _Phase.processing) return;
    if (state is! MemberDetailLoaded || state.isCheckingIn) return;
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
          title: 'Check in to a class',
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
          instanceName: _selected?.className ?? 'the class',
          result: loaded?.checkInResult,
          error: loaded?.checkInError,
        );
      case _Phase.pick:
        return MemberCheckInPickBody(
          gymId: widget.gymId,
          selectedKey:
              _selected == null ? null : CheckInSection.keyFor(_selected!),
          onSelect: (i) => setState(() => _selected = i),
        );
    }
  }

  Widget? _actions(MemberDetailLoaded? loaded) {
    switch (_phase) {
      case _Phase.processing:
        return null;
      case _Phase.result:
        if (loaded?.checkInError != null) {
          return checkInChoiceActions(
            primaryLabel: 'Try again',
            onPrimary: _submit,
            dismissLabel: 'Close',
          );
        }
        return checkInDoneActions(context);
      case _Phase.pick:
        return checkInChoiceActions(
          primaryLabel: 'Check in',
          onPrimary: _selected == null ? null : _submit,
          dismissLabel: 'Cancel',
        );
    }
  }
}
