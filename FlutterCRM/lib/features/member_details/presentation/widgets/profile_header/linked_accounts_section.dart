import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/presentation/widgets/dialogs/link_parent/link_parent_dialog.dart';
import 'package:crm/features/member_details/presentation/widgets/dialogs/link_parent/manage_linked_accounts_dialog.dart';
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
    final hasParent = member.linkedToAccount != null;
    final hasChildren = member.linkedAccounts.any(
      (a) => a.crmUserId != member.linkedToAccount,
    );
    final hasAnyLink = hasParent || hasChildren;
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
            text: hasAnyLink
                ? 'Manage Linked Accounts'
                : 'Link to Paying Account',
            onPressed: () => hasAnyLink
                ? ManageLinkedAccountsDialog.show(
                    context: context,
                    member: member,
                  )
                : _showLinkDialog(context),
          ),
        ),
      ],
    );
  }

  void _showLinkDialog(BuildContext context) {
    final state = context.read<MemberDetailBloc>().state;
    if (state is! MemberDetailLoaded) return;
    LinkParentDialog.show(
      context: context,
      crmUserId: member.crmUserId,
      candidates: state.allMembers,
    );
  }
}
