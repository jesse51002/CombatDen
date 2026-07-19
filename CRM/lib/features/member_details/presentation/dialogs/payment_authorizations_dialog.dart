import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/auth/role_policy.dart';
import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/data/models/linked_account.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/member_summary.dart';
import 'package:crm/features/member_details/presentation/dialogs/link_parent_dialog.dart';
import 'package:crm/features/member_details/presentation/dialogs/remove_authorization_dialog.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/authorize_direction.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_link_member_dialog.dart';
import 'package:crm/features/member_details/presentation/widgets/membership_display_helpers.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/view_switcher.dart';

/// Edit a member's payment authorizations (both directions).
///
/// Rebuilds live from [MemberDetailBloc] so an add / remove reflects without
/// reopening. Two switchable sections: "Authorized to pay" (people this member
/// may pay for) and "Authorized to receive payment" (people who may pay for
/// this member). Add is sign-gated (the payer signs the waiver) but otherwise
/// unconditional; Remove cancels the memberships funded across that one
/// relationship after a preview.
class PaymentAuthorizationsDialog extends StatefulWidget {
  const PaymentAuthorizationsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<MemberDetailBloc>(),
        child: const PaymentAuthorizationsDialog(),
      ),
    );
  }

  @override
  State<PaymentAuthorizationsDialog> createState() =>
      _PaymentAuthorizationsDialogState();
}

class _PaymentAuthorizationsDialogState
    extends State<PaymentAuthorizationsDialog> {
  /// 0 = Can Pay For (this member is the payer);
  /// 1 = Can Receive Payments (others pay for this member).
  int _section = 0;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MemberDetailBloc, MemberDetailState>(
      builder: (context, state) {
        if (state is! MemberDetailLoaded) {
          return const AppDialog(
            title: 'Payment authorizations',
            body: SizedBox(
              height: DesignConstants.dialogProcessingHeight,
              child: Center(child: AppSpinner()),
            ),
          );
        }
        final member = state.member;
        final isPay = _section == 0;
        final accounts =
            isPay ? member.authorizedToPayFor : member.authorizedPayers;
        // Removing an authorized-payer link (which cascades a cancellation) is
        // owner/admin-only; adding a link + viewing the roster stay open to
        // front desk.
        final canRemove = selectedGym.role?.canRemovePayerLink ?? false;
        return AppDialog(
          title: 'Payment authorizations',
          maxWidth: DesignConstants.dialogContentMaxWidth,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DesignConstants.spacingLarge,
            children: [
              const _Description(),
              ViewSwitcher(
                labels: const [
                  'Can Pay For',
                  'Can Receive Payments',
                ],
                selectedIndex: _section,
                onSelected: (i) => setState(() => _section = i),
              ),
              _SectionList(
                isPay: isPay,
                accounts: accounts,
                member: member,
                canRemove: canRemove,
                onRemove: (a) => _onRemove(member, a, isPay),
              ),
              AppOutlineButton(
                fullWidth: true,
                text: isPay
                    ? 'Add someone to pay for'
                    : 'Add an authorized payer',
                borderRadius: DesignConstants.radiusSmall,
                onPressed: () =>
                    _onAdd(member, state.allMembers, isPay),
              ),
            ],
          ),
          actions: AppDialogActions(
            primaryLabel: 'Done',
            primaryOnPressed: () => Navigator.of(context).pop(),
          ),
        );
      },
    );
  }

  /// Resolve (payee, payer) for the relationship in this section and open the
  /// remove dialog (which shows the cost preview, confirms, and dispatches the
  /// cascading remove). This popup rebuilds live off the bloc afterward.
  void _onRemove(
    MemberDetailResponse member,
    LinkedAccount account,
    bool isPay,
  ) {
    // "Can Pay For": this member pays for `account` (payee = account).
    // "Can Receive Payments": `account` pays for this member (payee = member).
    final payeeId = isPay ? account.memberId : member.memberId;
    final payerId = isPay ? member.memberId : account.memberId;
    // The payer is the focused member ("Can Pay For") or the linked account
    // ("Can Receive Payments") — attribute the preview with their photo.
    final payerPhotoUrl = isPay ? member.photoUrl : account.photoUrl;
    RemoveAuthorizationDialog.show(
      context: context,
      payeeMemberId: payeeId,
      payerMemberId: payerId,
      accountName: account.fullName,
      fallbackMonthly: member.totalMonthlyRecurringPrice,
      payerPhotoUrl: payerPhotoUrl,
    );
  }

  /// Open the right sign-gated add flow for the active section. Excludes the
  /// member themselves and anyone already in the section.
  Future<void> _onAdd(
    MemberDetailResponse member,
    List<MemberSummary> allMembers,
    bool isPay,
  ) async {
    final existing = (isPay
            ? member.authorizedToPayFor
            : member.authorizedPayers)
        .map((a) => a.memberId)
        .toSet();
    final candidates = allMembers
        .where(
          (m) =>
              m.memberId != member.memberId &&
              !existing.contains(m.memberId),
        )
        .toList();

    if (isPay) {
      // This member is the payer; pick who they will pay for (they sign).
      await StartLinkMemberDialog.show(
        context: context,
        direction: AuthorizeDirection.addPayee,
        anchorMemberId: member.memberId,
        anchorName: member.fullName,
        candidates: candidates,
      );
    } else {
      // Pick a payer for this member (the payer signs).
      await LinkParentDialog.show(
        context: context,
        subjectMemberId: member.memberId,
        subjectName: member.fullName,
        candidates: candidates,
      );
    }
    // The add flow dispatches the link mutation; the bloc refetches and this
    // BlocBuilder rebuilds with the new roster — nothing more to do here.
  }
}

class _Description extends StatelessWidget {
  const _Description();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Control who can pay for whom. Adding needs the payer to sign the gym’s '
      'waiver; removing a relationship cancels the recurring memberships it '
      'funds.',
      style: DesignConstants.h3Regular.copyWith(
        color: DesignConstants.text2nd,
      ),
    );
  }
}

/// The recurring memberships funded across the (viewed member, [account])
/// relationship — exactly what removing it would cancel. "Can Pay For" reads
/// the viewed member's `paysFor` roster for the payee; "Can Receive Payments"
/// reads the viewed member's own recurring memberships paid by that payer.
List<String> _fundedPlanNames(
  MemberDetailResponse member,
  LinkedAccount account,
  bool isPay,
) {
  if (isPay) {
    for (final p in member.paysFor) {
      if (p.memberId == account.memberId) {
        return p.memberships.map((m) => m.planName).toList();
      }
    }
    return const [];
  }
  return fundedRecurringMemberships(member.memberships, account.memberId)
      .map((m) => m.planName)
      .toList();
}

class _SectionList extends StatelessWidget {
  final bool isPay;
  final List<LinkedAccount> accounts;
  final MemberDetailResponse member;

  /// Whether the caller may remove a link (owner/admin). When false the
  /// per-row Remove action is hidden; the roster itself stays visible.
  final bool canRemove;
  final ValueChanged<LinkedAccount> onRemove;

  const _SectionList({
    required this.isPay,
    required this.accounts,
    required this.member,
    required this.canRemove,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (accounts.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(DesignConstants.paddingSmall),
        decoration: BoxDecoration(
          color: DesignConstants.backgroundColor,
          borderRadius:
              BorderRadius.circular(DesignConstants.radiusSmall),
        ),
        child: Text(
          isPay
              ? 'This member isn’t authorized to pay for anyone yet.'
              : 'No one is authorized to pay for this member yet.',
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text2nd,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: accounts
          .map(
            (a) => _AuthRow(
              account: a,
              planNames: _fundedPlanNames(member, a, isPay),
              canRemove: canRemove,
              onRemove: () => onRemove(a),
            ),
          )
          .toList(),
    );
  }
}

class _AuthRow extends StatelessWidget {
  final LinkedAccount account;
  final List<String> planNames;

  /// Whether the Remove action shows (owner/admin only).
  final bool canRemove;
  final VoidCallback onRemove;

  const _AuthRow({
    required this.account,
    required this.planNames,
    required this.canRemove,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.backgroundColor,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        border: Border.all(color: DesignConstants.divider),
      ),
      child: Row(
        spacing: DesignConstants.spacingMedium,
        children: [
          CircleAvatar(
            radius: DesignConstants.iconSizeMedium,
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: DesignConstants.spacingTiny,
              children: [
                Text(
                  account.fullName,
                  style: DesignConstants.h3,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  planNames.isEmpty
                      ? 'No active memberships'
                      : 'Cancels: ${planNames.join(', ')}',
                  style: DesignConstants.pSmall.copyWith(
                    color: planNames.isEmpty
                        ? DesignConstants.text3rd
                        : DesignConstants.text2nd,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (canRemove)
            TextButton.icon(
              onPressed: onRemove,
              icon: Icon(
                Symbols.close_sharp,
                size: DesignConstants.iconSizeSmall,
                weight: DesignConstants.iconWeight,
                color: DesignConstants.badRed,
              ),
              label: Text(
                'Remove',
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.badRed,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
