import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/features/employees/bloc/employees_bloc.dart';
import 'package:crm/features/employees/bloc/employees_event.dart';
import 'package:crm/features/employees/bloc/employees_state.dart';
import 'package:crm/features/employees/data/models/employee_create_request.dart';
import 'package:crm/features/employees/presentation/dialogs/add_employee_form.dart';
import 'package:crm/features/employees/presentation/dialogs/add_employee_success_view.dart';
import 'package:crm/features/employees/presentation/dialogs/employee_dialog_steps.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';

enum _AddStep { form, submitting, success }

/// Adds a gym staff member. Runs the form → submitting → success step machine,
/// riding the bloc's dedicated invite success token so the terminal step fires
/// against committed state, never fire-and-pop. The success step shows the
/// copyable email-based sign-in instructions (the point of the surface).
class AddEmployeeDialog extends StatefulWidget {
  const AddEmployeeDialog({super.key});

  static Future<void> show({required BuildContext context}) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BlocProvider.value(
        value: context.read<EmployeesBloc>(),
        child: const AddEmployeeDialog(),
      ),
    );
  }

  @override
  State<AddEmployeeDialog> createState() => _AddEmployeeDialogState();
}

class _AddEmployeeDialogState extends State<AddEmployeeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _bio = TextEditingController();

  late final EmployeesBloc _bloc;
  late final int _tokenAtOpen;

  EmployeeRole _role = EmployeeRole.trainer;
  _AddStep _step = _AddStep.form;
  String? _emailError;
  String _successFirstName = '';
  String _successEmail = '';

  @override
  void initState() {
    super.initState();
    _bloc = context.read<EmployeesBloc>();
    final s = _bloc.state;
    _tokenAtOpen = s is EmployeesLoaded ? s.inviteSuccess : 0;
    _bloc.add(const EmployeesMutationOutcomeCleared());
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    _bio.dispose();
    super.dispose();
  }

  String? _nullIfEmpty(String v) => v.trim().isEmpty ? null : v.trim();

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _emailError = null;
      _step = _AddStep.submitting;
    });
    _bloc.add(EmployeeInviteSubmitted(EmployeeCreateRequest(
      employeeType: _role,
      firstName: _firstName.text.trim(),
      lastName: _lastName.text.trim(),
      email: _email.text.trim(),
      phone: _nullIfEmpty(_phone.text),
      employeePublicDescription: _nullIfEmpty(_bio.text),
    )));
  }

  void _onState(BuildContext context, EmployeesState state) {
    if (state is! EmployeesLoaded) return;
    if (_step != _AddStep.submitting) return;
    final err = state.mutationError;
    if (err != null) {
      setState(() {
        _emailError = err;
        _step = _AddStep.form;
      });
      _bloc.add(const EmployeesMutationOutcomeCleared());
      return;
    }
    if (state.inviteSuccess != _tokenAtOpen) {
      final invited = state.lastInvitedEmployee;
      setState(() {
        _successFirstName = invited?.firstName ?? _firstName.text.trim();
        _successEmail = invited?.email ?? _email.text.trim();
        _step = _AddStep.success;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<EmployeesBloc, EmployeesState>(
      listenWhen: (prev, curr) => curr is EmployeesLoaded,
      listener: _onState,
      child: AppDialog(
        title: 'Add employee',
        showCloseButton: _step != _AddStep.submitting,
        body: _buildBody(),
        actions: _buildActions(),
      ),
    );
  }

  Widget _buildBody() {
    switch (_step) {
      case _AddStep.form:
        return Form(
          key: _formKey,
          child: AddEmployeeForm(
            firstName: _firstName,
            lastName: _lastName,
            email: _email,
            phone: _phone,
            bio: _bio,
            role: _role,
            onRoleChanged: (r) => setState(() => _role = r),
            emailError: _emailError,
          ),
        );
      case _AddStep.submitting:
        return const EmployeeDialogProcessing(label: 'Adding…');
      case _AddStep.success:
        return AddEmployeeSuccessView(
          firstName: _successFirstName,
          email: _successEmail,
        );
    }
  }

  Widget _buildActions() {
    switch (_step) {
      case _AddStep.form:
        return AppDialogActions(
          primaryLabel: 'Add employee',
          primaryOnPressed: _submit,
          secondaryLabel: 'Cancel',
          secondaryOnPressed: () => Navigator.of(context).pop(),
        );
      case _AddStep.submitting:
        return const AppDialogActions(
          primaryLabel: 'Add employee',
          isLoading: true,
          primaryOnPressed: null,
        );
      case _AddStep.success:
        return AppDialogActions(
          primaryLabel: 'Done',
          primaryOnPressed: () => Navigator.of(context).pop(),
        );
    }
  }
}
