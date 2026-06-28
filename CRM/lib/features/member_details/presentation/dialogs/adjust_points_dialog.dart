import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';

/// Dialog for manually awarding or deducting points on
/// behalf of a member.
///
/// Accepts a signed integer amount (positive = award,
/// negative = deduct) and dispatches [AdjustPointsRequested]
/// to [MemberDetailBloc]. A backend 400 (deduct below zero)
/// surfaces as an [actionError] on the loaded state.
class AdjustPointsDialog extends StatefulWidget {
  final String memberId;
  final String memberName;
  final int currentBalance;

  const AdjustPointsDialog({
    super.key,
    required this.memberId,
    required this.memberName,
    required this.currentBalance,
  });

  static Future<void> show({
    required BuildContext context,
    required String memberId,
    required String memberName,
    required int currentBalance,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<MemberDetailBloc>(),
        child: AdjustPointsDialog(
          memberId: memberId,
          memberName: memberName,
          currentBalance: currentBalance,
        ),
      ),
    );
  }

  @override
  State<AdjustPointsDialog> createState() =>
      _AdjustPointsDialogState();
}

class _AdjustPointsDialogState
    extends State<AdjustPointsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  String? _validationError;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  String? _validate(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Enter a non-zero amount';
    }
    final parsed = int.tryParse(value.trim());
    if (parsed == null) return 'Enter a whole number';
    if (parsed == 0) return 'Amount must not be zero';
    return null;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final amount =
        int.tryParse(_amountController.text.trim());
    if (amount == null || amount == 0) return;

    context.read<MemberDetailBloc>().add(
          AdjustPointsRequested(
            memberId: widget.memberId,
            amount: amount,
          ),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Award / adjust points',
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingLarge,
          children: [
            Text(
              '${widget.memberName} — current balance: '
              '${widget.currentBalance} pts',
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
            CustomTextField(
              controller: _amountController,
              label: 'Points adjustment',
              hintText: 'e.g. 100 or -50',
              keyboardType:
                  const TextInputType.numberWithOptions(
                signed: true,
                decimal: false,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'^-?\d*'),
                ),
              ],
              validator: _validate,
            ),
            if (_validationError != null)
              Text(
                _validationError!,
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.badRed,
                ),
              ),
          ],
        ),
      ),
      actions: AppDialogActions(
        primaryLabel: 'Apply',
        primaryOnPressed: _submit,
        secondaryLabel: 'Cancel',
        secondaryOnPressed: () =>
            Navigator.of(context).pop(),
      ),
    );
  }
}
