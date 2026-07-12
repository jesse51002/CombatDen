import 'package:flutter/material.dart';

import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/validators.dart';
import 'package:crm/features/employees/presentation/dialogs/add_employee_form.dart';
import 'package:crm/shared/widgets/class_row/instructor_avatar.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';
import 'package:crm/shared/widgets/form/app_dropdown_field.dart';
import 'package:crm/shared/widgets/form/image_upload_picker_field.dart';

/// The Edit-employee form fields. Owner-row guards are reused disabled
/// affordances, not invented ones: an [isOwnerRow] shows a disabled "Owner"
/// role dropdown (the owner can't be demoted here); [readOnly] (an admin
/// viewing the owner) disables every field, drops the photo picker for a static
/// preview, and the dialog hides Save.
class EditEmployeeForm extends StatelessWidget {
  final String fullName;
  final TextEditingController firstName;
  final TextEditingController lastName;
  final TextEditingController email;
  final TextEditingController phone;
  final TextEditingController bio;
  final EmployeeRole role;
  final ValueChanged<EmployeeRole> onRoleChanged;
  final bool isOwnerRow;
  final bool readOnly;
  final String? photoUrl;
  final ValueChanged<String> onPhotoUploaded;
  final String? error;

  const EditEmployeeForm({
    super.key,
    required this.fullName,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.bio,
    required this.role,
    required this.onRoleChanged,
    required this.isOwnerRow,
    required this.readOnly,
    required this.photoUrl,
    required this.onPhotoUploaded,
    this.error,
  });

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  String? _optionalEmail(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    return Validators.validateEmail(v.trim());
  }

  @override
  Widget build(BuildContext context) {
    final enabled = !readOnly;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        if (readOnly)
          Text(
            'You can view but not edit the owner\'s profile.',
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
        CustomTextField(
          controller: firstName,
          label: 'First name',
          enabled: enabled,
          validator: _required,
        ),
        CustomTextField(
          controller: lastName,
          label: 'Last name',
          enabled: enabled,
          validator: _required,
        ),
        CustomTextField(
          controller: email,
          label: 'Email',
          enabled: enabled,
          keyboardType: TextInputType.emailAddress,
          validator: _optionalEmail,
        ),
        CustomTextField(
          controller: phone,
          label: 'Phone',
          enabled: enabled,
          keyboardType: TextInputType.phone,
        ),
        _RoleField(
          isOwnerRow: isOwnerRow,
          role: role,
          onRoleChanged: enabled ? onRoleChanged : null,
        ),
        CustomTextField(
          controller: bio,
          label: 'Bio',
          enabled: enabled,
          maxLines: 4,
          minLines: 3,
        ),
        if (readOnly)
          _ReadOnlyPhoto(fullName: fullName, photoUrl: photoUrl)
        else
          ImageUploadPickerField(
            label: 'Profile photo',
            category: 'employee',
            aspectRatio: 1,
            imageUrl: photoUrl,
            onUploaded: onPhotoUploaded,
          ),
        if (error != null)
          Text(
            error!,
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.badRed,
            ),
          ),
      ],
    );
  }
}

/// The role picker — disabled + "Owner" for the owner row (owner can't be
/// demoted here), otherwise the admin/front_desk/trainer choices. A null
/// [onRoleChanged] disables it (read-only mode).
class _RoleField extends StatelessWidget {
  final bool isOwnerRow;
  final EmployeeRole role;
  final ValueChanged<EmployeeRole>? onRoleChanged;

  const _RoleField({
    required this.isOwnerRow,
    required this.role,
    required this.onRoleChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (isOwnerRow) {
      return AppDropdownField<EmployeeRole>(
        label: 'Role',
        value: EmployeeRole.owner,
        items: const [
          DropdownMenuItem<EmployeeRole>(
            value: EmployeeRole.owner,
            child: Text('Owner'),
          ),
        ],
        onChanged: null,
      );
    }
    return AppDropdownField<EmployeeRole>(
      label: 'Role',
      value: role,
      items: [
        for (final r in AddEmployeeForm.roleChoices)
          DropdownMenuItem<EmployeeRole>(value: r, child: Text(r.label)),
      ],
      onChanged: onRoleChanged == null
          ? null
          : (r) {
              if (r != null) onRoleChanged!(r);
            },
    );
  }
}

/// A static square photo preview shown in read-only mode (no tappable picker).
class _ReadOnlyPhoto extends StatelessWidget {
  final String fullName;
  final String? photoUrl;

  const _ReadOnlyPhoto({required this.fullName, required this.photoUrl});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text('Profile photo', style: DesignConstants.h2),
        InstructorAvatar(
          photoUrl: photoUrl,
          name: fullName,
          diameter: DesignConstants.iconSizeBig * 3,
        ),
      ],
    );
  }
}
