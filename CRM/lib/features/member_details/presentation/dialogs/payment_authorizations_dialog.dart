import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/data/models/linked_account.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/member_summary.dart';
import 'package:crm/features/member_details/data/models/remove_authorization_preview.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/member_details/presentation/dialogs/link_parent_dialog.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_link_member_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/billing_confirmation_dialog.dart';
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
  final MemberRepository _repository =
      MemberRepository(apiClient: ApiClient());

  /// 0 = Authorized to pay (this member is the payer);
  /// 1 = Authorized to receive payment (others pay for this member).
  int _section = 0;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MemberDetailBloc, MemberDetailState>(
      builder: (context, state) {
        if (state is! MemberDetailLoaded) {
          return const AppDialog(
            title: 'Payment authorizations',
            body: SizedBox(
              height: 120,
              child: Center(child: AppSpinner()),
            ),
          );
        }
        final member = state.member;
        final isPay = _section == 0;
        final accounts =
            isPay ? member.authorizedToPayFor : member.authorizedPayers;
        return AppDialog(
          title: 'Payment authorizations',
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DesignConstants.spacingLarge,
            children: [
              const _Description(),
              ViewSwitcher(
                labels: const [
                  'Authorized to pay',
                  'Authorized to receive payment',
                ],
                selectedIndex: _section,
                onSelected: (i) => setState(() => _section = i),
              ),
              _SectionList(
                isPay: isPay,
                accounts: accounts,
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

  /// Resolve (payee, payer) for the relationship in this section, preview the
  /// cascading cancel, confirm, then dispatch the remove.
  Future<void> _onRemove(
    MemberDetailResponse member,
    LinkedAccount account,
    bool isPay,
  ) async {
    // "Authorized to pay": this member pays for `account` (payee = account).
    // "Authorized to receive": `account` pays for this member (payee = member).
    final payeeId = isPay ? account.memberId : member.memberId;
    final payerId = isPay ? member.memberId : account.memberId;

    RemoveAuthorizationPreview preview;
    try {
      preview =
          await _repository.previewRemoveAuthorization(payeeId, payerId);
    } catch (_) {
      preview = const RemoveAuthorizationPreview();
    }
    if (!mounted) return;

    final effects = preview.memberships.isEmpty
        ? const [
            BillingEffect(
              icon: Symbols.link_off_sharp,
              text:
                  'No memberships will be cancelled — this only removes '
                  'the authorization.',
            ),
          ]
        : preview.memberships
            .map(
              (m) => BillingEffect(
                icon: Symbols.cancel_sharp,
                text:
                    'Cancel ${m.planName} '
                    '(${formatMinorUnits(m.totalPrice)}/mo)',
              ),
            )
            .toList();

    final confirmed = await BillingConfirmationDialog.show(
      context: context,
      title: 'Remove authorization',
      summary:
          'Remove ${account.fullName} from this relationship? This '
          'cancels the recurring memberships funded between them.',
      confirmLabel: 'Remove & cancel',
      confirmColor: DesignConstants.badRed,
      effects: effects,
      warning: preview.memberships.isNotEmpty
          ? 'Cancelled memberships stop billing after the current cycle.'
          : null,
    );
    if (!confirmed || !mounted) return;
    context.read<MemberDetailBloc>().add(
          RemoveAuthorizationRequested(
            memberId: payeeId,
            payerMemberId: payerId,
          ),
        );
    Navigator.of(context).pop();
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
        payerMemberId: member.memberId,
        payerName: member.fullName,
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
      'Payment authorizations control who may pay for whom. An authorized '
      'payer can be set as the payer on this member’s memberships; this '
      'member can be set as the payer for anyone they’re authorized to pay '
      'for. Adding requires the payer to sign the gym’s waiver. Removing a '
      'relationship cancels the recurring memberships funded across it.',
      style: DesignConstants.pSmall.copyWith(
        color: DesignConstants.text2nd,
      ),
    );
  }
}

class _SectionList extends StatelessWidget {
  final bool isPay;
  final List<LinkedAccount> accounts;
  final ValueChanged<LinkedAccount> onRemove;

  const _SectionList({
    required this.isPay,
    required this.accounts,
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
          .map((a) => _AuthRow(account: a, onRemove: () => onRemove(a)))
          .toList(),
    );
  }
}

class _AuthRow extends StatelessWidget {
  final LinkedAccount account;
  final VoidCallback onRemove;

  const _AuthRow({required this.account, required this.onRemove});

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
            child: Text(
              account.fullName,
              style: DesignConstants.h3,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
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
