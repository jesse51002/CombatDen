import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/data/models/linked_account.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/presentation/dialogs/link_parent_dialog.dart';
import 'package:crm/features/member_details/presentation/dialogs/unlink_parent_dialog.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';

/// Linked-accounts block for the profile header.
///
/// Asymmetric by role: a dependent member shows the single
/// **Authorized Payer** they can navigate to (no family-wide
/// browsing); an authorized payer shows every account it is
/// authorized to pay for. Plus the link / unlink affordance.
/// When the member has no link at all, only a "Link to Paying
/// Account" button shows. Each chip navigates via
/// [onLinkedAccountTap].
class LinkedAccountsSection extends StatelessWidget {
  final MemberDetailResponse member;
  final ValueChanged<String>? onLinkedAccountTap;

  const LinkedAccountsSection({
    super.key,
    required this.member,
    this.onLinkedAccountTap,
  });

  bool get _hasParent => member.linkedToAccount != null;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingMedium,
      children: [
        ..._relationshipBlock(),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: _hasParent
              ? AppOutlineButton(
                  fullWidth: true,
                  text: 'Unlink Authorized Payer',
                  borderColor: DesignConstants.badRed,
                  textColor: DesignConstants.badRed,
                  borderRadius: DesignConstants.radiusSmall,
                  onPressed: () => UnlinkParentDialog.show(
                    context: context,
                    subjectName: member.fullName,
                  ),
                )
              : AppOutlineButton(
                  fullWidth: true,
                  text: 'Add Authorized Payer',
                  borderRadius: DesignConstants.radiusSmall,
                  onPressed: () => _openLink(context),
                ),
        ),
      ],
    );
  }

  /// The heading + chip(s) for this member's billing relationship:
  /// a dependent's single Authorized Payer, or an authorized payer's
  /// list of accounts they may pay for. Empty for an unlinked solo.
  List<Widget> _relationshipBlock() {
    if (_hasParent) {
      final payer = _payerAccount();
      if (payer == null) return const [];
      return [
        Text('Authorized Payer', style: DesignConstants.h2),
        _LinkedAccountChip(
          account: payer,
          onTap: onLinkedAccountTap != null
              ? () => onLinkedAccountTap!(payer.memberId)
              : null,
        ),
      ];
    }
    final dependents = member.linkedAccounts;
    if (dependents.isEmpty) return const [];
    return [
      Text('Authorized to pay for', style: DesignConstants.h2),
      Wrap(
        spacing: DesignConstants.spacingMedium,
        runSpacing: DesignConstants.spacingMedium,
        alignment: WrapAlignment.center,
        children: dependents
            .map(
              (a) => _LinkedAccountChip(
                account: a,
                onTap: onLinkedAccountTap != null
                    ? () => onLinkedAccountTap!(a.memberId)
                    : null,
              ),
            )
            .toList(),
      ),
    ];
  }

  /// The account this member's memberships are authorized to be paid
  /// by — their linked parent — resolved from the linked-accounts list.
  LinkedAccount? _payerAccount() {
    for (final a in member.linkedAccounts) {
      if (a.memberId == member.linkedToAccount) return a;
    }
    return null;
  }

  void _openLink(BuildContext context) {
    final state = context.read<MemberDetailBloc>().state;
    if (state is! MemberDetailLoaded) return;
    LinkParentDialog.show(
      context: context,
      subjectMemberId: member.memberId,
      candidates: state.allMembers,
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
                          ? account.firstName[0]
                              .toUpperCase()
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
