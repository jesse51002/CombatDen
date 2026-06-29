import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/features/schedule/bloc/schedule_bloc.dart';
import 'package:crm/features/schedule/bloc/schedule_state.dart';
import 'package:crm/features/schedule/presentation/dialogs/schedule_cancel_views.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';

enum _Phase { confirm, processing, success }

/// Manage one class occurrence from the schedule board: update who attended
/// (batch check-in, primary for a non-cancelled day), edit the class, or cancel
/// just this day ([cancellable] only). Shares the board's [ScheduleBloc].
class ClassCancelDialog extends StatefulWidget {
  final String className;
  final DateTime classDate;
  final bool cancellable;
  final bool isCancelled;

  /// Edit the class / cancel this occurrence / open batch check-in.
  final VoidCallback onEdit;
  final VoidCallback onCancelInstance;
  final VoidCallback onUpdateAttendees;

  const ClassCancelDialog({
    super.key,
    required this.className,
    required this.classDate,
    required this.cancellable,
    required this.isCancelled,
    required this.onEdit,
    required this.onCancelInstance,
    required this.onUpdateAttendees,
  });

  static Future<void> show({
    required BuildContext context,
    required String className,
    required DateTime classDate,
    required bool cancellable,
    required bool isCancelled,
    required VoidCallback onEdit,
    required VoidCallback onCancelInstance,
    required VoidCallback onUpdateAttendees,
  }) {
    final bloc = context.read<ScheduleBloc>();
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider<ScheduleBloc>.value(
        value: bloc,
        child: ClassCancelDialog(
          className: className,
          classDate: classDate,
          cancellable: cancellable,
          isCancelled: isCancelled,
          onEdit: onEdit,
          onCancelInstance: onCancelInstance,
          onUpdateAttendees: onUpdateAttendees,
        ),
      ),
    );
  }

  @override
  State<ClassCancelDialog> createState() => _ClassCancelDialogState();
}

class _ClassCancelDialogState extends State<ClassCancelDialog> {
  _Phase _phase = _Phase.confirm;
  String? _inlineError;
  int _successBaseline = 0;

  void _confirmCancel() {
    final state = context.read<ScheduleBloc>().state;
    _successBaseline = state is ScheduleLoaded ? state.actionSuccessCount : 0;
    setState(() {
      _inlineError = null;
      _phase = _Phase.processing;
    });
    widget.onCancelInstance();
  }

  void _onState(BuildContext context, ScheduleState state) {
    if (_phase != _Phase.processing) return;
    if (state is! ScheduleLoaded || state.isMutating) return;
    if (state.actionSuccessCount > _successBaseline) {
      setState(() => _phase = _Phase.success);
    } else if (state.actionError != null) {
      setState(() {
        _phase = _Phase.confirm;
        _inlineError = state.actionError;
      });
    }
  }

  void _edit() {
    Navigator.of(context).pop();
    widget.onEdit();
  }

  void _updateAttendees() {
    Navigator.of(context).pop();
    widget.onUpdateAttendees();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ScheduleBloc, ScheduleState>(
      listener: _onState,
      child: AppDialog(
        title: widget.className,
        body: _body(),
        actions: _actions(),
      ),
    );
  }

  Widget _body() => switch (_phase) {
        _Phase.processing => const ScheduleCancelProcessing(),
        _Phase.success => const ScheduleCancelSuccess(
            message: 'This class is cancelled for that day.',
          ),
        _Phase.confirm => ClassCancelConfirmBody(
            classDate: widget.classDate,
            cancellable: widget.cancellable,
            isCancelled: widget.isCancelled,
            inlineError: _inlineError,
          ),
      };

  Widget? _actions() {
    final canCheckIn = !widget.isCancelled;
    return switch (_phase) {
      _Phase.processing => null,
      _Phase.success => AppDialogActions(
          primaryLabel: 'Done',
          primaryOnPressed: () => Navigator.of(context).pop(),
        ),
      _Phase.confirm => AppDialogActions(
          primaryLabel: canCheckIn ? 'Update attendees' : 'Edit class details',
          primaryOnPressed: canCheckIn ? _updateAttendees : _edit,
          secondaryLabel: canCheckIn ? 'Edit class details' : null,
          secondaryOnPressed: canCheckIn ? _edit : null,
          destructiveLabel: widget.cancellable ? 'Cancel this class' : null,
          destructiveOnPressed: widget.cancellable ? _confirmCancel : null,
        ),
    };
  }
}
