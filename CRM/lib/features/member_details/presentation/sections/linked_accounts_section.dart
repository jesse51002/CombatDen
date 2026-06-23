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

/// Authorized-payer block for the profile header.
///
/// Many-to-many: a member can have many authorized payers (who may
/// pay for them) AND be authorized to pay for many others. Both
/// directions render here — "Authorized Payers" (with per-payer
/// Remove + an Add that runs the sign-waiver flow) and "Authorized
/// to pay for" (display-only chips; manage each from that member's
/// own page). Each chip navigates via [onLinkedAccountTap].
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
            onRemove: (account) => UnlinkParentDialog.show(
              context: context,
              payeeMemberId: member.memberId,
              payerMemberId: account.memberId,
              payerName: account.fullName,
            ),
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
            text: 'Add Authorized Payer',
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
      subjectName: member.fullName,
      candidates: state.allMembers,
    );
  }
}

/// A titled roster of authorized-payer chips. [onRemove], when set,
/// adds a Remove affordance to each chip (the Authorized Payers
/// direction); display-only otherwise.
class _Roster extends StatelessWidget {
  final String title;
  final List<LinkedAccount> accounts;
  final ValueChanged<String>? onTap;
  final ValueChanged<LinkedAccount>? onRemove;

  const _Roster({
    required this.title,
    required this.accounts,
    this.onTap,
    this.onRemove,
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
                  onTap: onTap != null
                      ? () => onTap!(a.memberId)
                      : null,
                  onRemove:
                      onRemove != null ? () => onRemove!(a) : null,
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
  final VoidCallback? onRemove;

  const _LinkedAccountChip({
    required this.account,
    this.onTap,
    this.onRemove,
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
            if (onRemove != null)
              Semantics(
                label: 'Remove ${account.fullName}',
                button: true,
                child: InkWell(
                  onTap: onRemove,
                  borderRadius: BorderRadius.circular(
                    DesignConstants.radiusBig,
                  ),
                  child: Icon(
                    Symbols.close_sharp,
                    size: DesignConstants.iconSizeSmall,
                    weight: DesignConstants.iconWeight,
                    color: DesignConstants.text2nd,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
