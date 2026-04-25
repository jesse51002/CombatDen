import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/members_management_update_request.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';

/// Form dialog for editing a member's profile. Fields
/// are pre-filled from the current [MemberDetailResponse]
/// and the confirm action dispatches an
/// [EditMemberRequested] with only the changed values.
class EditMemberDialog extends StatefulWidget {
  final MemberDetailResponse member;

  const EditMemberDialog({
    super.key,
    required this.member,
  });

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
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _address;
  late final TextEditingController _ecName;
  late final TextEditingController _ecPhone;
  late final TextEditingController _ecEmail;

  @override
  void initState() {
    super.initState();
    final m = widget.member;
    _firstName = TextEditingController(text: m.firstName);
    _lastName = TextEditingController(text: m.lastName);
    _phone = TextEditingController(
      text: m.personalInfo.phone ?? '',
    );
    _email = TextEditingController(
      text: m.personalInfo.email ?? '',
    );
    _address = TextEditingController(
      text: m.personalInfo.address ?? '',
    );
    _ecName = TextEditingController(
      text: m.personalInfo.emergencyContactName ?? '',
    );
    _ecPhone = TextEditingController(
      text: m.personalInfo.emergencyContactPhone ?? '',
    );
    _ecEmail = TextEditingController(
      text: m.personalInfo.emergencyContactEmail ?? '',
    );
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    _ecName.dispose();
    _ecPhone.dispose();
    _ecEmail.dispose();
    super.dispose();
  }

  String? _diff(
    TextEditingController controller,
    String? original,
  ) {
    final next = controller.text.trim();
    if (next == (original ?? '')) return null;
    return next.isEmpty ? null : next;
  }

  MembersManagementUpdateRequest _buildRequest() {
    final m = widget.member;
    return MembersManagementUpdateRequest(
      firstName: _diff(_firstName, m.firstName),
      lastName: _diff(_lastName, m.lastName),
      phone: _diff(_phone, m.personalInfo.phone),
      email: _diff(_email, m.personalInfo.email),
      address: _diff(_address, m.personalInfo.address),
      emergencyContactName: _diff(
        _ecName,
        m.personalInfo.emergencyContactName,
      ),
      emergencyContactPhone: _diff(
        _ecPhone,
        m.personalInfo.emergencyContactPhone,
      ),
      emergencyContactEmail: _diff(
        _ecEmail,
        m.personalInfo.emergencyContactEmail,
      ),
    );
  }

  void _onSave() {
    final req = _buildRequest();
    context
        .read<MemberDetailBloc>()
        .add(EditMemberRequested(req));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Edit Member',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingMedium,
        children: [
          CustomTextField(
            controller: _firstName,
            label: 'First name',
          ),
          CustomTextField(
            controller: _lastName,
            label: 'Last name',
          ),
          CustomTextField(
            controller: _phone,
            label: 'Phone',
            keyboardType: TextInputType.phone,
          ),
          CustomTextField(
            controller: _email,
            label: 'Email',
            keyboardType: TextInputType.emailAddress,
          ),
          CustomTextField(
            controller: _address,
            label: 'Address',
          ),
          Text(
            'Emergency Contact',
            style: DesignConstants.h2.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
          CustomTextField(
            controller: _ecName,
            label: 'Name',
          ),
          CustomTextField(
            controller: _ecPhone,
            label: 'Phone',
            keyboardType: TextInputType.phone,
          ),
          CustomTextField(
            controller: _ecEmail,
            label: 'Email',
            keyboardType: TextInputType.emailAddress,
          ),
        ],
      ),
      actions: AppDialogActions(
        primaryLabel: 'Save',
        primaryOnPressed: _onSave,
        secondaryLabel: 'Cancel',
      ),
    );
  }
}
