import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/payer_invoice_change.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/member_details/presentation/widgets/invoice_preview_section.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// Confirms removing a payment authorization. Shows the cost preview ONLY when
/// the payer is actually affected — i.e. they fund a membership that will be
/// cancelled (the backend's membership-level `affected` flag). When nothing is
/// funded across the relationship, it says so plainly: removing changes no
/// billing. On confirm it dispatches [RemoveAuthorizationRequested] (the backend
/// cancels those memberships, then de-authorizes the pair).
///
/// Pair-scoped, so a single payer's outcome is shown. [payeeMemberId] is the
/// member being paid for; [payerMemberId] is the payer being removed.
class RemoveAuthorizationDialog extends StatefulWidget {
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
  State<RemoveAuthorizationDialog> createState() =>
      _RemoveAuthorizationDialogState();
}

class _RemoveAuthorizationDialogState
    extends State<RemoveAuthorizationDialog> {
  final MemberRepository _repository =
      MemberRepository(apiClient: ApiClient());
  late final Future<List<PayerInvoiceChange>> _preview =
      _repository.previewRemoveAuthorization(
    widget.payeeMemberId,
    widget.payerMemberId,
  );

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Remove authorization',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          Text(
            'Removing ${widget.accountName} cancels the recurring memberships '
            'funded across this relationship.',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
          FutureBuilder<List<PayerInvoiceChange>>(
            future: _preview,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SizedBox(
                  height: 80,
                  child: Center(child: AppSpinner()),
                );
              }
              final affected = (snapshot.data ?? const [])
                  .where((c) => c.affected)
                  .toList();
              if (affected.isEmpty) {
                return _NoChangeNote();
              }
              // Pair-scoped → one affected payer.
              final change = affected.first;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: DesignConstants.spacingMedium,
                children: [
                  Text(
                    'Billing after removal',
                    style: DesignConstants.h3.copyWith(
                      color: DesignConstants.text2nd,
                    ),
                  ),
                  InvoicePreviewSection(
                    loadPreview: () async => change.preview,
                    loadCurrent: () => _repository
                        .getUpcomingInvoice(change.payerMemberId),
                    showDueNow: false,
                    recurringFallbackMonthly: widget.fallbackMonthly,
                    emptyLabel: 'No recurring billing change.',
                    errorLabel: 'Could not load the billing preview.',
                  ),
                ],
              );
            },
          ),
        ],
      ),
      actions: AppDialogActions(
        primaryLabel: 'Remove & cancel',
        primaryColor: DesignConstants.badRed,
        primaryOnPressed: () {
          context.read<MemberDetailBloc>().add(
                RemoveAuthorizationRequested(
                  memberId: widget.payeeMemberId,
                  payerMemberId: widget.payerMemberId,
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

class _NoChangeNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.backgroundColor,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      ),
      child: Text(
        'No memberships are funded across this relationship — removing it '
        'changes no billing.',
        style: DesignConstants.p.copyWith(
          color: DesignConstants.text2nd,
        ),
      ),
    );
  }
}
