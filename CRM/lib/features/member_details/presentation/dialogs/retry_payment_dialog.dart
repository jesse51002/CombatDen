import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/presentation/dialogs/retry_payment_confirm_view.dart';
import 'package:crm/features/member_details/presentation/dialogs/retry_payment_success_view.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

enum _Step { confirm, processing, success }

/// Re-charges the card ALREADY on file against an overdue membership's
/// open invoice — the cash-free sibling of the mark-paid-cash dialog
/// (same handles, no card input; the backend bills the payer's saved
/// default). Submitting drives an in-dialog spinner → success step; a
/// decline drops back to the confirm step with the backend's message
/// and the Retry button still live. The outcome rides the bloc's
/// dedicated channel (`isRetryingPayment` / `retryPaymentSuccess` /
/// `retryPaymentError`) so the screen-level overlay + error dialog
/// never fire while this dialog is open (mirrors the cancel-one-time
/// and charge-card dialogs).
class RetryPaymentDialog extends StatefulWidget {
  final int amount;
  final String currency;
  final String itemId;
  final String coveredMemberId;
  final String payerName;

  const RetryPaymentDialog({
    super.key,
    required this.amount,
    required this.currency,
    required this.itemId,
    required this.coveredMemberId,
    required this.payerName,
  });

  static Future<void> show({
    required BuildContext context,
    required int amount,
    required String currency,
    required String itemId,
    required String coveredMemberId,
    required String payerName,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BlocProvider.value(
        value: context.read<MemberDetailBloc>(),
        child: RetryPaymentDialog(
          amount: amount,
          currency: currency,
          itemId: itemId,
          coveredMemberId: coveredMemberId,
          payerName: payerName,
        ),
      ),
    );
  }

  @override
  State<RetryPaymentDialog> createState() =>
      _RetryPaymentDialogState();
}

class _RetryPaymentDialogState extends State<RetryPaymentDialog> {
  late final MemberDetailBloc _bloc;
  late final int _successTokenAtOpen;
  _Step _step = _Step.confirm;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bloc = context.read<MemberDetailBloc>();
    final st = _bloc.state;
    _successTokenAtOpen =
        st is MemberDetailLoaded ? st.retryPaymentSuccess : 0;
    // Clear any prior decline so a stale failure never flashes.
    _bloc.add(const RetryCardPaymentOutcomeCleared());
  }

  void _submit() {
    setState(() {
      _error = null;
      _step = _Step.processing;
    });
    _bloc.add(
      RetryCardPaymentRequested(
        itemId: widget.itemId,
        memberId: widget.coveredMemberId,
      ),
    );
  }

  void _onState(BuildContext context, MemberDetailState state) {
    if (state is! MemberDetailLoaded) return;
    if (_step != _Step.processing) return;
    final err = state.retryPaymentError;
    if (err != null) {
      setState(() {
        _error = err;
        _step = _Step.confirm;
      });
      _bloc.add(const RetryCardPaymentOutcomeCleared());
      return;
    }
    if (state.retryPaymentSuccess != _successTokenAtOpen) {
      setState(() => _step = _Step.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<MemberDetailBloc, MemberDetailState>(
      listenWhen: (prev, curr) => curr is MemberDetailLoaded,
      listener: _onState,
      child: AppDialog(
        title: 'Retry payment',
        showCloseButton: _step != _Step.processing,
        body: _buildBody(),
        actions: _buildActions(),
      ),
    );
  }

  Widget _buildBody() {
    switch (_step) {
      case _Step.confirm:
        return RetryPaymentConfirmView(
          amount: widget.amount,
          currency: widget.currency,
          payerName: widget.payerName,
          error: _error,
        );
      case _Step.processing:
        return const _RetryProcessing();
      case _Step.success:
        return RetryPaymentSuccessView(
          amountCents: widget.amount,
          currency: widget.currency,
          payerName: widget.payerName,
        );
    }
  }

  Widget _buildActions() {
    switch (_step) {
      case _Step.confirm:
        return AppDialogActions(
          primaryLabel:
              _error == null ? 'Retry payment' : 'Try again',
          primaryOnPressed: _submit,
          secondaryLabel: 'Cancel',
          secondaryOnPressed: () => Navigator.of(context).pop(),
        );
      case _Step.processing:
        return const AppDialogActions(
          primaryLabel: 'Retry payment',
          isLoading: true,
          primaryOnPressed: null,
        );
      case _Step.success:
        return AppDialogActions(
          primaryLabel: 'Done',
          primaryOnPressed: () => Navigator.of(context).pop(),
        );
    }
  }
}

class _RetryProcessing extends StatelessWidget {
  const _RetryProcessing();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: DesignConstants.dialogProcessingHeight,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingMedium,
          children: [
            const AppSpinner(),
            Text(
              'Charging the card on file…',
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
