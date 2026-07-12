import 'package:flutter/material.dart';

import 'package:crm/core/constants/app_constants.dart';
import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/validators.dart';
import 'package:crm/features/member_details/data/models/members_management_create_request.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';
import 'package:crm/shared/widgets/form/image_upload_picker_field.dart';

/// Reusable new-member form — mirrors `EditMemberDialog`'s fields, but email
/// is REQUIRED and the photo is an optional curated-pool pick or upload.
///
/// It does NOT own submission: a host holds a `GlobalKey<MemberCreateFormState>`,
/// calls [MemberCreateFormState.validate], then
/// [MemberCreateFormState.buildRequest] and dispatches to a
/// `MemberCreateBloc`. Two-column rows keep the form compact.
class MemberCreateForm extends StatefulWidget {
  const MemberCreateForm({super.key});

  @override
  State<MemberCreateForm> createState() => MemberCreateFormState();
}

class MemberCreateFormState extends State<MemberCreateForm> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _ecName = TextEditingController();
  final _ecPhone = TextEditingController();
  final _ecEmail = TextEditingController();

  /// CDN URL of the chosen member photo (upload or pool pick); null = none.
  String? _photoUrl;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    _address.dispose();
    _ecName.dispose();
    _ecPhone.dispose();
    _ecEmail.dispose();
    super.dispose();
  }

  /// Runs form validation and returns whether every field passed.
  bool validate() => _formKey.currentState?.validate() ?? false;

  /// The trimmed value, or null when empty (an omitted optional field).
  String? _opt(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  /// Assembles the wire request for [gymId]. Call after [validate].
  MembersManagementCreateRequest buildRequest(String gymId) {
    return MembersManagementCreateRequest(
      gymId: gymId,
      firstName: _firstName.text.trim(),
      lastName: _lastName.text.trim(),
      email: _email.text.trim(),
      phone: _opt(_phone),
      address: _opt(_address),
      emergencyContactName: _opt(_ecName),
      emergencyContactPhone: _opt(_ecPhone),
      emergencyContactEmail: _opt(_ecEmail),
      photoUrl: _photoUrl,
    );
  }

  String? _requiredName(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    return null;
  }

  String? _requiredEmail(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return 'Required';
    return Validators.validateEmail(t);
  }

  String? _optionalEmail(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    return Validators.validateEmail(v.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          _FieldRow(children: [
            CustomTextField(
              controller: _firstName,
              label: 'First name',
              validator: _requiredName,
            ),
            CustomTextField(
              controller: _lastName,
              label: 'Last name',
              validator: _requiredName,
            ),
          ]),
          CustomTextField(
            controller: _email,
            label: 'Email',
            keyboardType: TextInputType.emailAddress,
            validator: _requiredEmail,
          ),
          _FieldRow(children: [
            CustomTextField(
              controller: _phone,
              label: 'Phone',
              keyboardType: TextInputType.phone,
            ),
            CustomTextField(
              controller: _address,
              label: 'Address',
            ),
          ]),
          _FieldRow(children: [
            CustomTextField(
              controller: _ecName,
              label: 'Emergency contact name',
            ),
            CustomTextField(
              controller: _ecPhone,
              label: 'Emergency contact phone',
              keyboardType: TextInputType.phone,
            ),
            CustomTextField(
              controller: _ecEmail,
              label: 'Emergency contact email',
              keyboardType: TextInputType.emailAddress,
              validator: _optionalEmail,
            ),
          ]),
          ImageUploadPickerField(
            label: 'Member photo',
            category: 'member',
            poolImages: AppConstants.memberDefaultPhotoUrls,
            onImageChosen: (url) =>
                setState(() => _photoUrl = url),
          ),
        ],
      ),
    );
  }
}

/// Lays its [children] out as equal-width columns on one row, so paired /
/// tripled fields read as a group.
class _FieldRow extends StatelessWidget {
  final List<Widget> children;

  const _FieldRow({required this.children});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        for (final child in children) Expanded(child: child),
      ],
    );
  }
}
