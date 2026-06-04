import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/card_on_file.dart';
import 'package:crm/features/member_details/presentation/widgets/member_detail_format.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';

/// One-time charge against the member's saved card. Collects
/// an amount (dollars) + a description, then dispatches
/// [ChargeCardRequested] with the amount in minor units.
class ChargeCardDialog extends StatefulWidget {
  final String memberName;
  final CardOnFile? card;

  const ChargeCardDialog({
    super.key,
    required this.memberName,
    this.card,
  });

  static Future<void> show({
    required BuildContext context,
    required String memberName,
    CardOnFile? card,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<MemberDetailBloc>(),
        child: ChargeCardDialog(
          memberName: memberName,
          card: card,
        ),
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

  void _submit() {
    final cents = parseDollarsToCents(_amount.text);
    final description = _description.text.trim();
    if (cents == null) {
      setState(
        () => _error = 'Enter a valid amount greater than \$0.',
      );
      return;
    }
    if (description.isEmpty) {
      setState(
        () => _error = 'Add a short reason for the charge.',
      );
      return;
    }
    context.read<MemberDetailBloc>().add(
          ChargeCardRequested(
            amount: cents,
            description: description,
          ),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    return AppDialog(
      title: 'Charge card',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingLarge,
        children: [
          Text(
            card == null
                ? 'Create a one-time charge on '
                    '${widget.memberName}’s account.'
                : 'Charge ${widget.memberName}’s '
                    '${card.brand} ···· ${card.lastFour}.',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text,
            ),
          ),
          CustomTextField(
            controller: _amount,
            label: 'Amount (USD)',
            hintText: '50.00',
            keyboardType:
                const TextInputType.numberWithOptions(
              decimal: true,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                RegExp(r'[0-9.,$]'),
              ),
            ],
          ),
          CustomTextField(
            controller: _description,
            label: 'Reason',
            hintText: 'Private session',
          ),
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
        primaryLabel: 'Charge',
        primaryOnPressed: _submit,
        secondaryLabel: 'Cancel',
        secondaryOnPressed: () =>
            Navigator.of(context).pop(),
      ),
    );
  }
}
