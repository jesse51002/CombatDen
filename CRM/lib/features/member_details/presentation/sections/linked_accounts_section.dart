import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/linked_account.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/presentation/dialogs/payment_authorizations_dialog.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';

/// Authorized-payer block for the profile header.
///
/// At-a-glance, read-only: shows both directions of the member's payment
/// authorizations — "Authorized Payers" (who may pay for them) and "Authorized
/// to pay for" (who they may pay for). Editing (add / remove) happens in the
/// "Modify Payment Authorizations" popup. Each chip navigates via
/// [onLinkedAccountTap].
class LinkedAccountsSection extends StatelessWidget {
  final MemberDetailResponse member;
  final ValueChanged<String>? onLinkedAccountTap;

  const LinkedAccountsSection({
    super.key,
    required this.member,
    this.onLinkedAccountTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingLarge,
      children: [
        if (member.authorizedPayers.isNotEmpty)
          _Roster(
            title: 'Authorized Payers',
            accounts: member.authorizedPayers,
            onTap: onLinkedAccountTap,
          ),
        if (member.authorizedToPayFor.isNotEmpty)
          _Roster(
            title: 'Authorized to pay for',
            accounts: member.authorizedToPayFor,
            onTap: onLinkedAccountTap,
          ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: AppOutlineButton(
            fullWidth: true,
            text: 'Modify Payment Authorizations',
            borderRadius: DesignConstants.radiusSmall,
            onPressed: () => PaymentAuthorizationsDialog.show(context),
          ),
        ),
      ],
    );
  }
}

/// A titled, read-only roster of authorized-payer chips.
class _Roster extends StatelessWidget {
  final String title;
  final List<LinkedAccount> accounts;
  final ValueChanged<String>? onTap;

  const _Roster({
    required this.title,
    required this.accounts,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(title, style: DesignConstants.h2),
        Wrap(
          spacing: DesignConstants.spacingMedium,
          runSpacing: DesignConstants.spacingMedium,
          alignment: WrapAlignment.center,
          children: accounts
              .map(
                (a) => _LinkedAccountChip(
                  account: a,
                  onTap:
                      onTap != null ? () => onTap!(a.memberId) : null,
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _LinkedAccountChip extends StatelessWidget {
  final LinkedAccount account;
  final VoidCallback? onTap;

  const _LinkedAccountChip({
    required this.account,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(
        DesignConstants.radiusBig,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.spacingMedium,
          vertical: DesignConstants.spacingSmall,
        ),
        decoration: BoxDecoration(
          color: DesignConstants.backgroundColor,
          borderRadius: BorderRadius.circular(
            DesignConstants.radiusBig,
          ),
          border: Border.all(
            color: DesignConstants.divider,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingMedium,
          children: [
            CircleAvatar(
              radius: DesignConstants.iconSizeSmall,
              backgroundColor: DesignConstants.surface,
              backgroundImage: account.photoUrl != null
                  ? NetworkImage(account.photoUrl!)
                  : null,
              child: account.photoUrl == null
                  ? Text(
                      account.firstName.isNotEmpty
                          ? account.firstName[0].toUpperCase()
                          : '?',
                      style: DesignConstants.pSmall.copyWith(
                        color: DesignConstants.text,
                      ),
                    )
                  : null,
            ),
            Flexible(
              child: Text(
                account.fullName,
                style: DesignConstants.h3.copyWith(
                  color: DesignConstants.text,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
