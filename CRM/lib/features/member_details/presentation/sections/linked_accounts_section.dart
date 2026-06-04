import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

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
/// Shows the family/group around this member: a chip per
/// linked account (the paying parent flagged green), plus
/// the link / unlink affordances. When the member has no
/// link at all, only a "Link to Paying Account" button
/// shows. Each chip can navigate to that member via
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
    final accounts = member.linkedAccounts;
    final hasAnyLink = _hasParent || accounts.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingMedium,
      children: [
        if (accounts.isNotEmpty) ...[
          Text(
            'Linked accounts',
            style: DesignConstants.h2,
          ),
          Wrap(
            spacing: DesignConstants.spacingMedium,
            runSpacing: DesignConstants.spacingMedium,
            alignment: WrapAlignment.center,
            children: accounts
                .map(
                  (a) => _LinkedAccountChip(
                    account: a,
                    isPayingAccount:
                        a.memberId == member.linkedToAccount,
                    onTap: onLinkedAccountTap != null
                        ? () =>
                            onLinkedAccountTap!(a.memberId)
                        : null,
                  ),
                )
                .toList(),
          ),
        ],
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: _hasParent
              ? AppOutlineButton(
                  fullWidth: true,
                  text: 'Unlink from paying account',
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
                  text: hasAnyLink
                      ? 'Link to a paying account'
                      : 'Link to paying account',
                  borderRadius: DesignConstants.radiusSmall,
                  onPressed: () => _openLink(context),
                ),
        ),
      ],
    );
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
  final bool isPayingAccount;
  final VoidCallback? onTap;

  const _LinkedAccountChip({
    required this.account,
    required this.isPayingAccount,
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
            color: isPayingAccount
                ? DesignConstants.goodGreen
                : DesignConstants.divider,
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
                isPayingAccount
                    ? '${account.fullName} · paying'
                    : account.fullName,
                style: DesignConstants.h3.copyWith(
                  color: isPayingAccount
                      ? DesignConstants.goodGreen
                      : DesignConstants.text,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isPayingAccount)
              Icon(
                Symbols.verified_sharp,
                size: DesignConstants.iconSizeSmall,
                weight: DesignConstants.iconWeight,
                color: DesignConstants.goodGreen,
              ),
          ],
        ),
      ),
    );
  }
}
