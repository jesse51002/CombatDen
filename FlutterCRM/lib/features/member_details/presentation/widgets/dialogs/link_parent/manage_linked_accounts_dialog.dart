import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/data/models/linked_account.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/member_details/presentation/widgets/dialogs/link_parent/link_child_dialog.dart';
import 'package:crm/features/member_details/presentation/widgets/dialogs/link_parent/unlink_parent_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';

/// Lists every linked account relationship on the member —
/// the paying parent (if any) and every linked child — with
/// a per-row Unlink button. Unlinking routes through
/// [UnlinkParentDialog] so the staff member sees the
/// billing preview before confirming.
class ManageLinkedAccountsDialog extends StatelessWidget {
  final MemberDetailResponse member;

  const ManageLinkedAccountsDialog({
    super.key,
    required this.member,
  });

  static Future<void> show({
    required BuildContext context,
    required MemberDetailResponse member,
  }) {
    final bloc = context.read<MemberDetailBloc>();
    final repository = context.read<MemberRepository>();
    return showDialog<void>(
      context: context,
      builder: (_) => RepositoryProvider.value(
        value: repository,
        child: BlocProvider.value(
          value: bloc,
          child: ManageLinkedAccountsDialog(member: member),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final parent = _parentAccount();
    final children = member.linkedAccounts
        .where((a) => a.crmUserId != member.linkedToAccount)
        .toList();
    final isEmpty = parent == null && children.isEmpty;
    final payerName = parent?.fullName ?? member.fullName;
    final payerPhotoUrl =
        parent?.photoUrl ?? member.photoUrl;
    final payerInitial = payerName.isNotEmpty
        ? payerName[0].toUpperCase()
        : '?';
    return AppDialog(
      title: 'Manage Linked Accounts',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingMedium,
        children: [
          _PayerHeader(
            name: payerName,
            photoUrl: payerPhotoUrl,
            initial: payerInitial,
          ),
          if (isEmpty)
            Text(
              'No linked accounts.',
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
            )
          else ...[
            if (parent != null)
              _LinkedAccountRow(
                account: parent,
                roleLabel: 'Paying account',
                onUnlink: () => _onUnlink(
                  context,
                  member.crmUserId,
                ),
              ),
            ...children.map(
              (a) => _LinkedAccountRow(
                account: a,
                roleLabel: 'Linked account',
                onUnlink: () => _onUnlink(
                  context,
                  a.crmUserId,
                ),
              ),
            ),
          ],
          AppOutlineButton(
            text: 'Link New Account',
            fullWidth: true,
            onPressed: () => _onLinkNew(context),
            borderRadius: DesignConstants.radiusSmall,
          ),
        ],
      ),
      actions: AppDialogActions(
        primaryLabel: 'Done',
        primaryOnPressed: () =>
            Navigator.of(context).pop(),
      ),
    );
  }

  LinkedAccount? _parentAccount() {
    final parentId = member.linkedToAccount;
    if (parentId == null) return null;
    for (final a in member.linkedAccounts) {
      if (a.crmUserId == parentId) return a;
    }
    return null;
  }

  void _onUnlink(
    BuildContext context,
    String crmUserId,
  ) {
    UnlinkParentDialog.show(
      context: context,
      crmUserId: crmUserId,
    );
  }

  void _onLinkNew(BuildContext context) {
    final payerId =
        member.linkedToAccount ?? member.crmUserId;
    LinkChildDialog.show(
      context: context,
      parentCrmUserId: payerId,
      gymId: member.gymId,
    );
  }
}

class _PayerHeader extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final String initial;

  const _PayerHeader({
    required this.name,
    required this.photoUrl,
    required this.initial,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: DesignConstants.spacingMedium,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: DesignConstants.card,
          backgroundImage: photoUrl != null
              ? NetworkImage(photoUrl!)
              : null,
          child: photoUrl == null
              ? Text(
                  initial,
                  style: DesignConstants.p.copyWith(
                    color: DesignConstants.text,
                  ),
                )
              : null,
        ),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
              children: [
                const TextSpan(
                  text: 'These accounts are paid for by ',
                ),
                TextSpan(
                  text: name,
                  style: DesignConstants.p.copyWith(
                    color: DesignConstants.text,
                  ),
                ),
                const TextSpan(text: '.'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LinkedAccountRow extends StatelessWidget {
  final LinkedAccount account;
  final String roleLabel;
  final VoidCallback onUnlink;

  const _LinkedAccountRow({
    required this.account,
    required this.roleLabel,
    required this.onUnlink,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(
        DesignConstants.spacingMedium,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.backgroundColor,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
        border: Border.all(
          color: DesignConstants.divider,
        ),
      ),
      child: Row(
        spacing: DesignConstants.spacingMedium,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: DesignConstants.card,
            backgroundImage: account.photoUrl != null
                ? NetworkImage(account.photoUrl!)
                : null,
            child: account.photoUrl == null
                ? Text(
                    account.firstName.isNotEmpty
                        ? account.firstName[0].toUpperCase()
                        : '?',
                    style: DesignConstants.p.copyWith(
                      color: DesignConstants.text,
                    ),
                  )
                : null,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: DesignConstants.spacingTiny,
              children: [
                Text(
                  account.fullName,
                  style: DesignConstants.h3,
                ),
                Text(
                  roleLabel,
                  style: DesignConstants.pSmall.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
              ],
            ),
          ),
          AppOutlineButton(
            text: 'Unlink',
            onPressed: onUnlink,
            borderRadius: DesignConstants.radiusSmall,
            borderColor: DesignConstants.badRed,
            textStyle: DesignConstants.h3.copyWith(
              color: DesignConstants.badRed,
            ),
          ),
        ],
      ),
    );
  }
}
