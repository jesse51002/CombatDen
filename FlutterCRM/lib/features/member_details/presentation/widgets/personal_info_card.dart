import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/personal_info.dart';
import 'package:crm/shared/widgets/info_row.dart';
import 'package:crm/shared/widgets/outlined_action_button.dart';
import 'package:crm/shared/widgets/section_card.dart';

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
        InfoRow(
          label: 'Number',
          value: personalInfo.phone,
          linkType: InfoRowLinkType.phone,
        ),
        InfoRow(
          label: 'Email',
          value: personalInfo.email,
          linkType: InfoRowLinkType.email,
        ),
        InfoRow(
          label: 'Address',
          value: personalInfo.address,
        ),
        // Emergency Contact subsection
        if (_hasEmergencyContact) ...[
          const SizedBox(
            height:
                DesignConstants.spacingLarge,
          ),
          Text(
            'Emergency Contact',
            style: DesignConstants.h3,
          ),
          const SizedBox(
            height:
                DesignConstants.spacingSmall,
          ),
          InfoRow(
            label: 'Name',
            value: personalInfo.emergencyContactName,
          ),
          InfoRow(
            label: 'Number',
            value: personalInfo.emergencyContactPhone,
            linkType: InfoRowLinkType.phone,
          ),
          InfoRow(
            label: 'Email',
            value: personalInfo.emergencyContactEmail,
            linkType: InfoRowLinkType.email,
          ),
        ],
        const SizedBox(
          height: DesignConstants.spacingLarge,
        ),
        OutlinedActionButton(
          label: 'View Waiver',
          onPressed: personalInfo.waiverId != null
              ? () {
                  // TODO: Navigate to waiver screen
                }
              : null,
        ),
      ],
    );
  }

  bool get _hasEmergencyContact =>
      personalInfo.emergencyContactName != null ||
      personalInfo.emergencyContactPhone != null ||
      personalInfo.emergencyContactEmail != null;
}
