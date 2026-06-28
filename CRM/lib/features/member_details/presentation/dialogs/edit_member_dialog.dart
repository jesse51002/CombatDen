import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/validators.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/members_management_update_request.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';
import 'package:crm/shared/widgets/form/image_upload_picker_field.dart';

/// Edits a member's identity + contact details — name,
/// email, phone, address, emergency contact, and photo —
/// and dispatches [EditMemberRequested] with a
/// [MembersManagementUpdateRequest] carrying only the
/// changed fields.
///
/// All of these are accepted by the merged
/// `MemberUpdateData` contract and persisted by the backend
/// (see the request model's contract note). Rank and
/// account linking have their own surfaces and are not
/// edited here.
class EditMemberDialog extends StatefulWidget {
  final MemberDetailResponse member;

  const EditMemberDialog({super.key, required this.member});

  static Future<void> show({
    required BuildContext context,
    required MemberDetailResponse member,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<MemberDetailBloc>(),
        child: EditMemberDialog(member: member),
      ),
    );
  }

  @override
  State<EditMemberDialog> createState() =>
      _EditMemberDialogState();
}

class _EditMemberDialogState extends State<EditMemberDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _ecName;
  late final TextEditingController _ecPhone;
  late final TextEditingController _ecEmail;
  /// CDN URL after a successful photo upload. Null = unchanged.
  String? _uploadedPhotoUrl;

  @override
  void initState() {
    super.initState();
    final m = widget.member;
    final pi = m.personalInfo;
    _firstName = TextEditingController(text: m.firstName);
    _lastName = TextEditingController(text: m.lastName);
    _email = TextEditingController(text: pi.email ?? '');
    _phone = TextEditingController(text: pi.phone ?? '');
    _address =
        TextEditingController(text: pi.address ?? '');
    _ecName = TextEditingController(
      text: pi.emergencyContactName ?? '',
    );
    _ecPhone = TextEditingController(
      text: pi.emergencyContactPhone ?? '',
    );
    _ecEmail = TextEditingController(
      text: pi.emergencyContactEmail ?? '',
    );
  }

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

  String? _requiredName(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    return null;
  }

  /// Email is optional here — only validate the format when
  /// something is typed.
  String? _optionalEmail(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    return Validators.validateEmail(v.trim());
  }

  /// The trimmed value when it differs from [original],
  /// else null so an unchanged field is omitted from the
  /// partial update.
  String? _diff(String value, String? original) {
    final v = value.trim();
    return v == (original ?? '').trim() ? null : v;
  }

  /// Like [_diff], but never sends an empty string — the
  /// backend's `EmailStr` rejects `''`, so an email can be
  /// changed but not cleared through this dialog.
  String? _diffEmail(String value, String? original) {
    final v = value.trim();
    if (v.isEmpty) return null;
    return v == (original ?? '').trim() ? null : v;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final m = widget.member;
    final pi = m.personalInfo;
    context.read<MemberDetailBloc>().add(
          EditMemberRequested(
            MembersManagementUpdateRequest(
              firstName: _diff(_firstName.text, m.firstName),
              lastName: _diff(_lastName.text, m.lastName),
              email: _diffEmail(_email.text, pi.email),
              phone: _diff(_phone.text, pi.phone),
              address: _diff(_address.text, pi.address),
              emergencyContactName: _diff(
                _ecName.text,
                pi.emergencyContactName,
              ),
              emergencyContactPhone: _diff(
                _ecPhone.text,
                pi.emergencyContactPhone,
              ),
              emergencyContactEmail: _diffEmail(
                _ecEmail.text,
                pi.emergencyContactEmail,
              ),
              // Only send photo_url when a new upload
              // completed in this session.
              photoUrl: _uploadedPhotoUrl != null
                  ? _diff(_uploadedPhotoUrl!, m.photoUrl)
                  : null,
            ),
          ),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Edit member',
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingLarge,
          children: [
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
            CustomTextField(
              controller: _email,
              label: 'Email',
              keyboardType: TextInputType.emailAddress,
              validator: _optionalEmail,
            ),
            CustomTextField(
              controller: _phone,
              label: 'Phone',
              keyboardType: TextInputType.phone,
            ),
            CustomTextField(
              controller: _address,
              label: 'Address',
            ),
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
            ImageUploadPickerField(
              label: 'Member photo',
              category: 'member',
              imageUrl: widget.member.photoUrl,
              onUploaded: (url) =>
                  setState(() => _uploadedPhotoUrl = url),
            ),
          ],
        ),
      ),
      actions: AppDialogActions(
        primaryLabel: 'Save',
        primaryOnPressed: _submit,
        secondaryLabel: 'Cancel',
        secondaryOnPressed: () =>
            Navigator.of(context).pop(),
      ),
    );
  }
}
