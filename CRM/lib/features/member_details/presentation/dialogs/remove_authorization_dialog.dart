import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/member_details/presentation/widgets/invoice_preview_section.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';

/// Confirms removing a payment authorization, showing the COST preview first:
/// the payer's recurring bill current → new after cancelling the memberships
/// funded across the (payee, payer) relationship. On confirm it dispatches
/// [RemoveAuthorizationRequested] (the backend cancels those memberships, then
/// de-authorizes the pair).
///
/// Pair-scoped, so a single payer's change is shown. [payeeMemberId] is the
/// member being paid for; [payerMemberId] is the payer being removed.
class RemoveAuthorizationDialog extends StatelessWidget {
  final String payeeMemberId;
  final String payerMemberId;
  final String accountName;
  final int fallbackMonthly;

  const RemoveAuthorizationDialog({
    super.key,
    required this.payeeMemberId,
    required this.payerMemberId,
    required this.accountName,
    required this.fallbackMonthly,
  });

  static Future<void> show({
    required BuildContext context,
    required String payeeMemberId,
    required String payerMemberId,
    required String accountName,
    required int fallbackMonthly,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<MemberDetailBloc>(),
        child: RemoveAuthorizationDialog(
          payeeMemberId: payeeMemberId,
          payerMemberId: payerMemberId,
          accountName: accountName,
          fallbackMonthly: fallbackMonthly,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repository = MemberRepository(apiClient: ApiClient());
    return AppDialog(
      title: 'Remove authorization',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          Text(
            'Removing $accountName cancels the recurring memberships funded '
            'across this relationship. Review the billing change, then confirm.',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
          Text(
            'Billing after removal',
            style: DesignConstants.h3.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
          InvoicePreviewSection(
            // Pair-scoped → one payer; render that payer's recurring current →
            // new. The cost preview is the per-payer list's single entry.
            loadPreview: () async {
              final changes = await repository.previewRemoveAuthorization(
                payeeMemberId,
                payerMemberId,
              );
              return changes.isEmpty ? null : changes.first.preview;
            },
            loadCurrent: () =>
                repository.getUpcomingInvoice(payerMemberId),
            showDueNow: false,
            recurringFallbackMonthly: fallbackMonthly,
            emptyLabel: 'No recurring billing change.',
            errorLabel: 'Could not load the billing preview.',
          ),
        ],
      ),
      actions: AppDialogActions(
        primaryLabel: 'Remove & cancel',
        primaryColor: DesignConstants.badRed,
        primaryOnPressed: () {
          context.read<MemberDetailBloc>().add(
                RemoveAuthorizationRequested(
                  memberId: payeeMemberId,
                  payerMemberId: payerMemberId,
                ),
              );
          Navigator.of(context).pop();
        },
        secondaryLabel: 'Cancel',
        secondaryOnPressed: () => Navigator.of(context).pop(),
      ),
    );
  }
}
