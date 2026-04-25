import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/card_on_file.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/billing_confirmation_dialog.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';

/// One-time card charge for an arbitrary amount and
/// description. Pops a [BillingConfirmationDialog] before
/// dispatching [ChargeCardRequested] to
/// `POST /member_memberships/charge-card`.
class ChargeCardDialog extends StatefulWidget {
  final MemberDetailResponse member;

  const ChargeCardDialog({
    super.key,
    required this.member,
  });

  static Future<void> show({
    required BuildContext context,
    required MemberDetailResponse member,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<MemberDetailBloc>(),
        child: ChargeCardDialog(member: member),
      ),
    );
  }

  @override
  State<ChargeCardDialog> createState() =>
      _ChargeCardDialogState();
}

class _ChargeCardDialogState extends State<ChargeCardDialog> {
  final _amount = TextEditingController();
  final _description = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  int? _amountMinorUnits() {
    final raw = _amount.text.trim();
    if (raw.isEmpty) return null;
    final dollars = double.tryParse(raw);
    if (dollars == null || dollars <= 0) return null;
    return (dollars * 100).round();
  }

  Future<void> _onConfirm() async {
    final desc = _description.text.trim();
    if (desc.isEmpty) {
      setState(() {
        _error = 'Enter a description for this charge.';
      });
      return;
    }
    final minor = _amountMinorUnits();
    if (minor == null) {
      setState(() {
        _error = 'Enter an amount greater than zero.';
      });
      return;
    }
    final card = widget.member.cardOnFile;
    if (card == null) {
      setState(() {
        _error =
            'No card on file. Add a card before charging.';
      });
      return;
    }

    final confirmed =
        await BillingConfirmationDialog.show(
      context: context,
      title: 'Confirm charge',
      summary:
          'You are about to run a real card charge '
          'against this member.',
      effects: [
        BillingEffect(
          icon: Symbols.payments_sharp,
          text:
              '${formatMinorUnits(minor)} will be charged '
              'immediately to ${_formatCard(card)}.',
        ),
        BillingEffect(
          icon: Symbols.receipt_long_sharp,
          text: 'Reason: $desc',
        ),
      ],
      warning:
          'Charges are not reversible from this screen. '
          'Use Refund if you need to return the money.',
      confirmLabel: 'Charge ${formatMinorUnits(minor)}',
      confirmColor: DesignConstants.primaryColor,
    );
    if (!confirmed || !mounted) return;

    context.read<MemberDetailBloc>().add(
          ChargeCardRequested(
            amount: minor,
            description: desc,
          ),
        );
    Navigator.of(context).pop();
  }

  String _formatCard(CardOnFile card) {
    return '${card.brand} •••• ${card.lastFour}';
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Charge Card',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingMedium,
        children: [
          Text(
            'Run a one-time charge against the member\'s '
            'card on file.',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
          CustomTextField(
            controller: _description,
            label: 'Description',
          ),
          _AmountField(controller: _amount),
          if (_error != null)
            Text(
              _error!,
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.badRed,
              ),
            ),
        ],
      ),
      actions: AppDialogActions(
        primaryLabel: 'Review Charge',
        primaryOnPressed: _onConfirm,
        secondaryLabel: 'Cancel',
      ),
    );
  }
}

class _AmountField extends StatelessWidget {
  final TextEditingController controller;

  const _AmountField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(
          'Amount',
          style: DesignConstants.h2,
        ),
        TextFormField(
          controller: controller,
          keyboardType:
              const TextInputType.numberWithOptions(
            decimal: true,
            signed: false,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(
              RegExp(r'^\d*\.?\d{0,2}'),
            ),
          ],
          style: DesignConstants.h2.copyWith(
            color: DesignConstants.text,
          ),
          decoration: InputDecoration(
            prefixIcon: Padding(
              padding: const EdgeInsets.only(
                left: 16,
                right: 4,
              ),
              child: Text(
                '\$',
                style: DesignConstants.h2.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 0,
              minHeight: 0,
            ),
            suffixIcon: Padding(
              padding: const EdgeInsets.only(
                left: 4,
                right: 16,
              ),
              child: Text(
                'USD',
                style: DesignConstants.p.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
            ),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 0,
              minHeight: 0,
            ),
            hintText: '0.00',
            hintStyle: DesignConstants.h2.copyWith(
              color: DesignConstants.text
                  .withValues(alpha: 0.4),
            ),
            filled: true,
            fillColor: DesignConstants.card,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 16,
            ),
            border: _border(DesignConstants.text),
            enabledBorder: _border(DesignConstants.text),
            focusedBorder:
                _border(DesignConstants.primaryColor),
          ),
        ),
      ],
    );
  }

  OutlineInputBorder _border(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(
        DesignConstants.radiusBig,
      ),
      borderSide: BorderSide(color: color, width: 2),
    );
  }
}
