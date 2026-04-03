import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/presentation/widgets/membership_carousel/freeze_cancel_modal.dart';
import 'package:crm/features/member_details/presentation/widgets/profile_header/linked_account_chip.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/subtitle_section.dart';

/// Section showing linked accounts the member pays for.
class PayingForSection extends StatelessWidget {
  final MembershipInfo membership;
  final List<MembershipInfo> memberships;
  final void Function(String crmUserId)?
      onLinkedAccountTap;

  const PayingForSection({
    super.key,
    required this.membership,
    required this.memberships,
    this.onLinkedAccountTap,
  });

  @override
  Widget build(BuildContext context) {
    return SubtitleSection(
      title: 'Paying Membership For',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(
          DesignConstants.paddingSmall,
        ),
        decoration: BoxDecoration(
          color: DesignConstants.card,
          borderRadius: BorderRadius.circular(
            DesignConstants.radiusSmall,
          ),
        ),
        child: Column(
          spacing: DesignConstants.spacingMedium,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: DesignConstants.spacingLarge,
              runSpacing: DesignConstants.spacingSmall,
              children: membership.payingFor
                  .map(
                    (a) => LinkedAccountChip(
                      account: a,
                      onTap: onLinkedAccountTap != null
                          ? () => onLinkedAccountTap!(
                                a.crmUserId,
                              )
                          : null,
                    ),
                  )
                  .toList(),
            ),
            AppOutlineButton(
              fullWidth: true,
              text: 'Manage Their Membership',
              onPressed: () {
                FreezeCancelModal.show(
                  context: context,
                  memberships: memberships,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
