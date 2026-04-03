import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/linked_account.dart';

/// A chip displaying a linked account avatar and name.
/// Tappable to navigate to that member's detail page.
class LinkedAccountChip extends StatelessWidget {
  final LinkedAccount account;
  final VoidCallback? onTap;
  final bool isPayingAccount;

  const LinkedAccountChip({
    super.key,
    required this.account,
    this.onTap,
    this.isPayingAccount = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(
        DesignConstants.radiusBig,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 36.0 / 2,
            backgroundColor: DesignConstants.card,
            backgroundImage: account.photoUrl != null
                ? NetworkImage(account.photoUrl!)
                : null,
            child: account.photoUrl == null
                ? Text(
                    account.firstName[0].toUpperCase(),
                    style: DesignConstants.pSmall.copyWith(
                      color: DesignConstants.text,
                    ),
                  )
                : null,
          ),
          const SizedBox(
            width:
                DesignConstants.spacingMedium,
          ),
          Text(
            isPayingAccount
                ? '${account.fullName} (paying account)'
                : account.fullName,
            style: DesignConstants.h3.copyWith(
              color: isPayingAccount
                  ? DesignConstants.goodGreen
                  : DesignConstants.text,
            ),
          ),
        ],
      ),
    );
  }
}
