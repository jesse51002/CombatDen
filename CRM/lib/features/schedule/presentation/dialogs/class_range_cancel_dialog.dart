import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/schedule/bloc/schedule_bloc.dart';
import 'package:crm/features/schedule/bloc/schedule_event.dart';
import 'package:crm/features/schedule/bloc/schedule_state.dart';
import 'package:crm/features/schedule/presentation/dialogs/schedule_cancel_views.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';

/// pick → processing → success (dismissed), or back to pick on error.
enum _Phase { pick, processing, success }

/// Cancel every occurrence of one class across a continuous date range. Opened
/// from the class edit form as a secondary action; shares the form's
/// [ScheduleBloc] (via `BlocProvider.value`) so a successful cancel reloads the
/// board the user returns to. Dispatches `ScheduleRangeCancelled`.
class ClassRangeCancelDialog extends StatefulWidget {
  final String classId;
  final String className;

  const ClassRangeCancelDialog({
    super.key,
    required this.classId,
    required this.className,
  });

  static Future<void> show({
    required BuildContext context,
    required String classId,
    required String className,
  }) {
    final bloc = context.read<ScheduleBloc>();
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider<ScheduleBloc>.value(
        value: bloc,
        child: ClassRangeCancelDialog(classId: classId, className: className),
      ),
    );
  }

  @override
  State<ClassRangeCancelDialog> createState() => _ClassRangeCancelDialogState();
}

class _ClassRangeCancelDialogState extends State<ClassRangeCancelDialog> {
  _Phase _phase = _Phase.pick;
  DateTime? _start;
  DateTime? _end;
  String? _inlineError;
  int _successBaseline = 0;

  void _confirm() {
    if (_start == null || _end == null) {
      setState(() => _inlineError = 'Pick both a start and an end date.');
      return;
    }
    if (_end!.isBefore(_start!)) {
      setState(() => _inlineError = 'The end date must be on or after start.');
      return;
    }
    final state = context.read<ScheduleBloc>().state;
    _successBaseline = state is ScheduleLoaded ? state.actionSuccessCount : 0;
    setState(() {
      _inlineError = null;
      _phase = _Phase.processing;
    });
    context.read<ScheduleBloc>().add(
          ScheduleRangeCancelled(
            classId: widget.classId,
            start: _start!,
            end: _end!,
          ),
        );
  }

  /// Watch the shared mutation channel: a settled bump past the baseline is
  /// our success; a set `actionError` is our failure.
  void _onState(BuildContext context, ScheduleState state) {
    if (_phase != _Phase.processing) return;
    if (state is! ScheduleLoaded || state.isMutating) return;
    if (state.actionSuccessCount > _successBaseline) {
      setState(() => _phase = _Phase.success);
    } else if (state.actionError != null) {
      setState(() {
        _phase = _Phase.pick;
        _inlineError = state.actionError;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ScheduleBloc, ScheduleState>(
      listener: _onState,
      child: AppDialog(
        title: 'Cancel a date range',
        body: _body(),
        actions: _actions(),
      ),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _Phase.processing:
        return const ScheduleCancelProcessing();
      case _Phase.success:
        return const ScheduleCancelSuccess(
          message: 'Every class in that range is cancelled.',
        );
      case _Phase.pick:
        return ClassRangeCancelPick(
          className: widget.className,
          start: _start,
          end: _end,
          onStart: (d) => setState(() => _start = d),
          onEnd: (d) => setState(() => _end = d),
          inlineError: _inlineError,
        );
    }
  }

  Widget? _actions() {
    if (_phase == _Phase.processing) return null;
    if (_phase == _Phase.success) {
      return AppDialogActions(
        primaryLabel: 'Done',
        primaryOnPressed: () => Navigator.of(context).pop(),
      );
    }
    return AppDialogActions(
      primaryLabel: 'Cancel range',
      primaryColor: DesignConstants.badRed,
      primaryOnPressed: _confirm,
      secondaryLabel: 'Back',
      secondaryOnPressed: () => Navigator.of(context).pop(),
    );
  }
}
