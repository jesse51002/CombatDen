import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/personal_info.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/info_table.dart';
import 'package:crm/shared/widgets/section_card.dart';
import 'package:crm/shared/widgets/subtitle_section.dart';

/// Card displaying member personal information
/// and emergency contact details.
class PersonalInfoCard extends StatelessWidget {
  final PersonalInfo personalInfo;

  const PersonalInfoCard({
    super.key,
    required this.personalInfo,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Personal Information',
      children: [
        _ContactInfoSection(personalInfo: personalInfo),
        if (_hasEmergencyContact) ...[
          _EmergencyContactSection(
            personalInfo: personalInfo,
          ),
        ],
        const Spacer(),
        _WaiverSection(personalInfo: personalInfo),
      ],
    );
  }

  bool get _hasEmergencyContact =>
      personalInfo.emergencyContactName != null ||
      personalInfo.emergencyContactPhone != null ||
      personalInfo.emergencyContactEmail != null;
}

class _ContactInfoSection extends StatelessWidget {
  final PersonalInfo personalInfo;

  const _ContactInfoSection({
    required this.personalInfo,
  });

  @override
  Widget build(BuildContext context) {
    return InfoTable(
      rows: [
        (
          _label('Number:'),
          _linkValue(personalInfo.phone),
        ),
        (
          _label('Email:'),
          _linkValue(personalInfo.email),
        ),
        (
          _label('Address:'),
          _plainValue(personalInfo.address),
        ),
      ],
    );
  }
}

class _EmergencyContactSection extends StatelessWidget {
  final PersonalInfo personalInfo;

  const _EmergencyContactSection({
    required this.personalInfo,
  });

  @override
  Widget build(BuildContext context) {
    return SubtitleSection(
      title: 'Emergency Contact',
      child: InfoTable(
        rowGap: DesignConstants.spacingMedium,
        rows: [
          (
            _label('Name:'),
            _plainValue(
              personalInfo.emergencyContactName,
            ),
          ),
          (
            _label('Number:'),
            _linkValue(
              personalInfo.emergencyContactPhone,
            ),
          ),
          (
            _label('Email:'),
            _linkValue(
              personalInfo.emergencyContactEmail,
            ),
          ),
        ],
      ),
    );
  }
}

class _WaiverSection extends StatelessWidget {
  final PersonalInfo personalInfo;

  const _WaiverSection({
    required this.personalInfo,
  });

  @override
  Widget build(BuildContext context) {
    return AppOutlineButton(
      fullWidth: true,
      text: 'View Waiver',
      onPressed: personalInfo.waiverId != null
          ? () {
              // TODO: Navigate to waiver screen
            }
          : null,
    );
  }
}

Widget _label(String text) {
  return Text(
    text,
    style: DesignConstants.h2.copyWith(
      color: DesignConstants.text2nd,
    ),
  );
}

Widget _plainValue(String? value) {
  return Text(
    value ?? '—',
    style: DesignConstants.h2,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
  );
}

Widget _linkValue(String? value) {
  if (value == null) {
    return Text('—', style: DesignConstants.h2);
  }
  return Builder(
    builder: (context) => GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: value));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Copied "$value" to clipboard'),
            duration: const Duration(seconds: 2),
          ),
        );
      },
      child: Text(
        value,
        style: DesignConstants.h2.copyWith(
          color: DesignConstants.hyperlink,
          decoration: TextDecoration.underline,
          decorationColor: DesignConstants.hyperlink,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );
}
