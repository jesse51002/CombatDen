import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/personal_info.dart';
import 'package:crm/features/member_details/presentation/dialogs/coming_soon_dialog.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/info_table.dart';
import 'package:crm/shared/widgets/section_card.dart';
import 'package:crm/shared/widgets/subtitle_section.dart';

/// Personal information + emergency contact display.
///
/// This is the read-only at-a-glance view; the same fields
/// (phone, address, emergency contact, email) are editable
/// through the Edit dialog, which the merged
/// `MemberUpdateData` contract accepts and persists. Phone
/// / email values copy to the clipboard on tap.
class PersonalInfoSection extends StatelessWidget {
  final PersonalInfo personalInfo;

  const PersonalInfoSection({
    super.key,
    required this.personalInfo,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingBig,
        children: [
          Text(
            'Personal information',
            style: DesignConstants.h2,
          ),
          InfoTable(
            rows: [
              (
                _label('Number'),
                _LinkValue(value: personalInfo.phone),
              ),
              (
                _label('Email'),
                _LinkValue(value: personalInfo.email),
              ),
              (
                _label('Address'),
                _plainValue(personalInfo.address),
              ),
            ],
          ),
          SubtitleSection(
            title: 'Emergency contact',
            child: InfoTable(
              rows: [
                (
                  _label('Name'),
                  _plainValue(
                    personalInfo.emergencyContactName,
                  ),
                ),
                (
                  _label('Number'),
                  _LinkValue(
                    value:
                        personalInfo.emergencyContactPhone,
                  ),
                ),
                (
                  _label('Email'),
                  _LinkValue(
                    value:
                        personalInfo.emergencyContactEmail,
                  ),
                ),
              ],
            ),
          ),
          AppOutlineButton(
            fullWidth: true,
            text: 'View waiver',
            borderRadius: DesignConstants.radiusSmall,
            onPressed: () => ComingSoonDialog.show(
              context: context,
              title: 'View waiver',
              message:
                  'Waiver viewing is pending — the storage '
                  'shape for waivers is not finalised on the '
                  'backend yet.',
            ),
          ),
        ],
      ),
    );
  }
}

Widget _label(String text) {
  return Text(
    '$text:',
    style: DesignConstants.p.copyWith(
      color: DesignConstants.text2nd,
    ),
  );
}

Widget _plainValue(String? value) {
  return Text(
    value ?? '—',
    style: DesignConstants.p,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
  );
}

class _LinkValue extends StatelessWidget {
  final String? value;

  const _LinkValue({required this.value});

  @override
  Widget build(BuildContext context) {
    final v = value;
    if (v == null) {
      return Text('—', style: DesignConstants.p);
    }
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: v));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Copied "$v" to clipboard'),
            duration: const Duration(seconds: 2),
          ),
        );
      },
      child: Text(
        v,
        style: DesignConstants.p.copyWith(
          color: DesignConstants.hyperlink,
          decoration: TextDecoration.underline,
          decorationColor: DesignConstants.hyperlink,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
