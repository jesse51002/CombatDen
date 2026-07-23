import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/employees/bloc/employees_bloc.dart';
import 'package:crm/features/employees/bloc/employees_event.dart';
import 'package:crm/features/employees/bloc/employees_state.dart';
import 'package:crm/features/employees/data/models/employee.dart';
import 'package:crm/features/employees/data/models/invite_status.dart';
import 'package:crm/features/employees/presentation/dialogs/employee_dialog_steps.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';

enum _RemoveStep { confirm, processing, done }

/// Removes an employee — a dedicated stepped dialog (NOT `ConfirmationModal`,
/// which dismisses on confirm with no visible outcome) so a destructive op
/// still ends in a visible terminal state. The confirm copy is status-aware,
/// and the primary is a solid red destructive button.
class RemoveEmployeeDialog extends StatefulWidget {
  final Employee employee;

  const RemoveEmployeeDialog({super.key, required this.employee});

  static Future<void> show({
    required BuildContext context,
    required Employee employee,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BlocProvider.value(
        value: context.read<EmployeesBloc>(),
        child: RemoveEmployeeDialog(employee: employee),
      ),
    );
  }

  @override
  State<RemoveEmployeeDialog> createState() => _RemoveEmployeeDialogState();
}

class _RemoveEmployeeDialogState extends State<RemoveEmployeeDialog> {
  late final EmployeesBloc _bloc;
  late final int _tokenAtOpen;
  _RemoveStep _step = _RemoveStep.confirm;
  String? _error;

  bool get _isInstructor =>
      widget.employee.inviteStatus == InviteStatus.none;

  String get _confirmTitle =>
      _isInstructor ? 'Remove this instructor?' : 'Remove $_name?';

  String get _name => widget.employee.fullName;

  String? get _confirmBody {
    switch (widget.employee.inviteStatus) {
      case InviteStatus.active:
      case InviteStatus.unknown:
        return 'They\'ll lose access to this gym\'s CRM.';
      case InviteStatus.pending:
        return null;
      case InviteStatus.none:
        return 'Classes keep their history; future slots show \'Instructor\'.';
    }
  }

  String get _doneTitle => _isInstructor ? 'Instructor removed' : '$_name removed';

  String get _doneDetail => _isInstructor
      ? 'Their class history is kept.'
      : 'They no longer have access to this gym.';

  @override
  void initState() {
    super.initState();
    _bloc = context.read<EmployeesBloc>();
    final s = _bloc.state;
    _tokenAtOpen = s is EmployeesLoaded ? s.removeSuccess : 0;
    _bloc.add(const EmployeesMutationOutcomeCleared());
  }

  void _submit() {
    setState(() {
      _error = null;
      _step = _RemoveStep.processing;
    });
    _bloc.add(EmployeeRemoveRequested(widget.employee.employeeId));
  }

  void _onState(BuildContext context, EmployeesState state) {
    if (state is! EmployeesLoaded) return;
    if (_step != _RemoveStep.processing) return;
    final err = state.mutationError;
    if (err != null) {
      setState(() {
        _error = err;
        _step = _RemoveStep.confirm;
      });
      _bloc.add(const EmployeesMutationOutcomeCleared());
      return;
    }
    if (state.removeSuccess != _tokenAtOpen) {
      setState(() => _step = _RemoveStep.done);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<EmployeesBloc, EmployeesState>(
      listenWhen: (prev, curr) => curr is EmployeesLoaded,
      listener: _onState,
      child: AppDialog(
        title: _step == _RemoveStep.done ? _doneTitle : _confirmTitle,
        showCloseButton: _step != _RemoveStep.processing,
        body: _buildBody(),
        actions: _buildActions(),
      ),
    );
  }

  Widget _buildBody() {
    switch (_step) {
      case _RemoveStep.confirm:
        final body = _confirmBody;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingMedium,
          children: [
            if (body != null)
              Text(
                body,
                style: DesignConstants.p.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
            if (_error != null)
              Text(
                _error!,
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.badRed,
                ),
              ),
          ],
        );
      case _RemoveStep.processing:
        return const EmployeeDialogProcessing(label: 'Removing…');
      case _RemoveStep.done:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingLarge,
          children: [
            Icon(
              Symbols.check_circle_sharp,
              weight: DesignConstants.iconWeight,
              size: DesignConstants.iconSizeBig,
              color: DesignConstants.goodGreen,
            ),
            Text(
              _doneDetail,
              textAlign: TextAlign.center,
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          ],
        );
    }
  }

  Widget _buildActions() {
    switch (_step) {
      case _RemoveStep.confirm:
        return AppDialogActions(
          primaryLabel: 'Remove',
          primaryColor: DesignConstants.badRed,
          primaryOnPressed: _submit,
          secondaryLabel: 'Cancel',
          secondaryOnPressed: () => Navigator.of(context).pop(),
        );
      case _RemoveStep.processing:
        return AppDialogActions(
          primaryLabel: 'Remove',
          primaryColor: DesignConstants.badRed,
          isLoading: true,
          primaryOnPressed: null,
        );
      case _RemoveStep.done:
        return AppDialogActions(
          primaryLabel: 'Done',
          primaryOnPressed: () => Navigator.of(context).pop(),
        );
    }
  }
}
