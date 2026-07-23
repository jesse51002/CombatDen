import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/employees/bloc/employees_bloc.dart';
import 'package:crm/features/employees/bloc/employees_event.dart';
import 'package:crm/features/employees/bloc/employees_state.dart';
import 'package:crm/features/employees/data/models/employee.dart';
import 'package:crm/features/employees/data/models/employee_update_request.dart';
import 'package:crm/features/employees/presentation/dialogs/edit_employee_form.dart';
import 'package:crm/features/employees/presentation/dialogs/employee_dialog_steps.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';

enum _EditStep { form, submitting, success }

/// Edits an employee's profile — prefilled, only changed fields sent, ending
/// in a visible terminal success (unlike the member edit dialog's fire-and-pop).
/// Owner-row guards: the owner's role can't be changed here, and an admin
/// viewing the owner sees the whole form read-only.
class EditEmployeeDialog extends StatefulWidget {
  final Employee employee;

  const EditEmployeeDialog({super.key, required this.employee});

  static Future<void> show({
    required BuildContext context,
    required Employee employee,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BlocProvider.value(
        value: context.read<EmployeesBloc>(),
        child: EditEmployeeDialog(employee: employee),
      ),
    );
  }

  @override
  State<EditEmployeeDialog> createState() => _EditEmployeeDialogState();
}

class _EditEmployeeDialogState extends State<EditEmployeeDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _bio;

  late final EmployeesBloc _bloc;
  late final int _tokenAtOpen;
  late EmployeeRole _role;
  String? _uploadedPhotoUrl;

  _EditStep _step = _EditStep.form;
  String? _error;

  bool get _isOwnerRow => widget.employee.employeeType == EmployeeRole.owner;
  bool get _readOnly =>
      _isOwnerRow && selectedGym.role != EmployeeRole.owner;

  @override
  void initState() {
    super.initState();
    final e = widget.employee;
    _firstName = TextEditingController(text: e.firstName);
    _lastName = TextEditingController(text: e.lastName);
    _email = TextEditingController(text: e.email ?? '');
    _phone = TextEditingController(text: e.phone ?? '');
    _bio = TextEditingController(text: e.employeePublicDescription ?? '');
    _role = e.employeeType;
    _bloc = context.read<EmployeesBloc>();
    final s = _bloc.state;
    _tokenAtOpen = s is EmployeesLoaded ? s.updateSuccess : 0;
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

  String? _diff(String value, String? original) {
    final v = value.trim();
    return v == (original ?? '').trim() ? null : v;
  }

  /// The backend's `EmailStr` rejects `''`, so an email can be changed but not
  /// cleared here (an empty field is treated as "unchanged").
  String? _diffEmail(String value, String? original) {
    final v = value.trim();
    if (v.isEmpty) return null;
    return v == (original ?? '').trim() ? null : v;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final e = widget.employee;
    final data = EmployeeUpdateData(
      firstName: _diff(_firstName.text, e.firstName),
      lastName: _diff(_lastName.text, e.lastName),
      email: _diffEmail(_email.text, e.email),
      phone: _diff(_phone.text, e.phone),
      employeePublicDescription:
          _diff(_bio.text, e.employeePublicDescription),
      employeePicUrl: _uploadedPhotoUrl != null
          ? _diff(_uploadedPhotoUrl!, e.employeePicUrl)
          : null,
      employeeType: _role != e.employeeType ? _role : null,
    );
    if (!data.hasChanges) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _error = null;
      _step = _EditStep.submitting;
    });
    _bloc.add(EmployeeUpdateSubmitted(e.employeeId, data));
  }

  void _onState(BuildContext context, EmployeesState state) {
    if (state is! EmployeesLoaded) return;
    if (_step != _EditStep.submitting) return;
    final err = state.mutationError;
    if (err != null) {
      setState(() {
        _error = err;
        _step = _EditStep.form;
      });
      _bloc.add(const EmployeesMutationOutcomeCleared());
      return;
    }
    if (state.updateSuccess != _tokenAtOpen) {
      setState(() => _step = _EditStep.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<EmployeesBloc, EmployeesState>(
      listenWhen: (prev, curr) => curr is EmployeesLoaded,
      listener: _onState,
      child: AppDialog(
        title: _readOnly ? 'Employee' : 'Edit employee',
        showCloseButton: _step != _EditStep.submitting,
        body: _buildBody(),
        actions: _buildActions(),
      ),
    );
  }

  Widget _buildBody() {
    switch (_step) {
      case _EditStep.form:
        return Form(
          key: _formKey,
          child: EditEmployeeForm(
            fullName: widget.employee.fullName,
            firstName: _firstName,
            lastName: _lastName,
            email: _email,
            phone: _phone,
            bio: _bio,
            role: _role,
            onRoleChanged: (r) => setState(() => _role = r),
            isOwnerRow: _isOwnerRow,
            readOnly: _readOnly,
            photoUrl: _uploadedPhotoUrl ?? widget.employee.employeePicUrl,
            onPhotoUploaded: (url) =>
                setState(() => _uploadedPhotoUrl = url),
            error: _error,
          ),
        );
      case _EditStep.submitting:
        return const EmployeeDialogProcessing(label: 'Saving…');
      case _EditStep.success:
        return EmployeeDialogSuccess(
          title: '${widget.employee.firstName}\'s profile updated',
          detail: 'The changes are saved.',
        );
    }
  }

  Widget _buildActions() {
    if (_readOnly) {
      return AppDialogActions(
        primaryLabel: 'Close',
        primaryOnPressed: () => Navigator.of(context).pop(),
      );
    }
    switch (_step) {
      case _EditStep.form:
        return AppDialogActions(
          primaryLabel: 'Save changes',
          primaryOnPressed: _submit,
          secondaryLabel: 'Cancel',
          secondaryOnPressed: () => Navigator.of(context).pop(),
        );
      case _EditStep.submitting:
        return const AppDialogActions(
          primaryLabel: 'Save changes',
          isLoading: true,
          primaryOnPressed: null,
        );
      case _EditStep.success:
        return AppDialogActions(
          primaryLabel: 'Done',
          primaryOnPressed: () => Navigator.of(context).pop(),
        );
    }
  }
}
