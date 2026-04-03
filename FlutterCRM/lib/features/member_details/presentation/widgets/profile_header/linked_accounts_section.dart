import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/presentation/widgets/profile_header/linked_account_chip.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';

/// Linked accounts chips and manage button.
class LinkedAccountsSection extends StatelessWidget {
  final MemberDetailResponse member;
  final void Function(String crmUserId)?
      onLinkedAccountTap;

  const LinkedAccountsSection({
    super.key,
    required this.member,
    this.onLinkedAccountTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(
          'Linked Accounts',
          style: DesignConstants.h1Regular,
        ),
        Wrap(
          spacing: DesignConstants.spacingLarge,
          runSpacing: DesignConstants.spacingLarge,
          alignment: WrapAlignment.center,
          children: member.linkedAccounts
              .map(
                (a) => LinkedAccountChip(
                  account: a,
                  isPayingAccount: a.crmUserId ==
                      member.linkedToAccount,
                  onTap: onLinkedAccountTap != null
                      ? () => onLinkedAccountTap!(
                            a.crmUserId,
                          )
                      : null,
                ),
              )
              .toList(),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 500,
          ),
          child: AppOutlineButton(
            fullWidth: true,
            text: 'Manage Linked accounts',
            onPressed: () {
              // TODO: Navigate to linked accounts management
            },
          ),
        ),
      ],
    );
  }
}
