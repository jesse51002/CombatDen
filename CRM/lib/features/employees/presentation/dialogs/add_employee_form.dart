import 'package:flutter/material.dart';

import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/validators.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';
import 'package:crm/shared/widgets/form/app_dropdown_field.dart';

/// The Add-employee form fields. The dialog owns the controllers, the selected
/// [role], and the [emailError] (a 409 backend `detail` shown verbatim under
/// Email); this widget just lays them out inside the dialog's [Form].
class AddEmployeeForm extends StatelessWidget {
  /// The roles a new hire may be given — never `owner` (that row is seeded at
  /// gym creation).
  static const List<EmployeeRole> roleChoices = [
    EmployeeRole.admin,
    EmployeeRole.frontDesk,
    EmployeeRole.trainer,
  ];

  final TextEditingController firstName;
  final TextEditingController lastName;
  final TextEditingController email;
  final TextEditingController phone;
  final TextEditingController bio;
  final EmployeeRole role;
  final ValueChanged<EmployeeRole> onRoleChanged;
  final String? emailError;

  const AddEmployeeForm({
    super.key,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.bio,
    required this.role,
    required this.onRoleChanged,
    this.emailError,
  });

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  String? _email(String? v) {
    if (v == null || v.trim().isEmpty) return 'Email is required';
    return Validators.validateEmail(v.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        CustomTextField(
          controller: firstName,
          label: 'First name',
          validator: _required,
        ),
        CustomTextField(
          controller: lastName,
          label: 'Last name',
          validator: _required,
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingSmall,
          children: [
            CustomTextField(
              controller: email,
              label: 'Email',
              keyboardType: TextInputType.emailAddress,
              validator: _email,
            ),
            Text(
              'Access is tied to this email — double-check it.',
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
            if (emailError != null)
              Text(
                emailError!,
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.badRed,
                ),
              ),
          ],
        ),
        CustomTextField(
          controller: phone,
          label: 'Phone',
          keyboardType: TextInputType.phone,
        ),
        AppDropdownField<EmployeeRole>(
          label: 'Role',
          value: role,
          items: [
            for (final r in roleChoices)
              DropdownMenuItem<EmployeeRole>(
                value: r,
                child: Text(r.label),
              ),
          ],
          onChanged: (r) {
            if (r != null) onRoleChanged(r);
          },
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingSmall,
          children: [
            CustomTextField(
              controller: bio,
              label: 'Bio',
              maxLines: 4,
              minLines: 3,
            ),
            Text(
              'Shown on classes.',
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
