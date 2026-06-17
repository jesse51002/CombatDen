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

/// One payer choice in the charge dialog — the member
/// themselves (self-pay) or their linked parent.
class ChargeCardPayer {
  final String memberId;
  final String name;

  const ChargeCardPayer({
    required this.memberId,
    required this.name,
  });
}

/// One-time charge billed to an explicit payer. Collects an
/// amount (dollars) + a description, lets staff pick WHO is
/// billed ([payers] — the member themselves or their linked
/// parent), then dispatches [ChargeCardRequested] with the
/// amount in minor units.
class ChargeCardDialog extends StatefulWidget {
  final String memberName;
  final CardOnFile? card;

  /// The valid payers for this charge (the member + their
  /// linked parent, when linked). Never empty.
  final List<ChargeCardPayer> payers;

  /// The pre-selected payer (defaults to the first entry).
  final String? initialPayerId;

  const ChargeCardDialog({
    super.key,
    required this.memberName,
    required this.payers,
    this.initialPayerId,
    this.card,
  });

  static Future<void> show({
    required BuildContext context,
    required String memberName,
    required List<ChargeCardPayer> payers,
    String? initialPayerId,
    CardOnFile? card,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<MemberDetailBloc>(),
        child: ChargeCardDialog(
          memberName: memberName,
          payers: payers,
          initialPayerId: initialPayerId,
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
  late String _payerId = widget.initialPayerId ??
      widget.payers.first.memberId;
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
            paidByMemberId: _payerId,
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
          if (widget.payers.length > 1)
            Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              spacing: DesignConstants.spacingSmall,
              children: [
                Text(
                  'Paid by',
                  style:
                      DesignConstants.pSmall.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
                Row(
                  spacing: DesignConstants.spacingMedium,
                  children: [
                    for (final p in widget.payers)
                      _PayerPill(
                        name: p.name,
                        selected:
                            p.memberId == _payerId,
                        onTap: () => setState(
                          () =>
                              _payerId = p.memberId,
                        ),
                      ),
                  ],
                ),
              ],
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

class _PayerPill extends StatelessWidget {
  final String name;
  final bool selected;
  final VoidCallback onTap;

  const _PayerPill({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(
        DesignConstants.radiusSmall,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.paddingSmall,
          vertical: DesignConstants.spacingMedium,
        ),
        decoration: BoxDecoration(
          color: selected
              ? DesignConstants.primaryColor10
              : DesignConstants.backgroundColor,
          borderRadius: BorderRadius.circular(
            DesignConstants.radiusSmall,
          ),
          border: Border.all(
            color: selected
                ? DesignConstants.primaryColor
                : DesignConstants.divider,
          ),
        ),
        child: Text(
          name,
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text,
            fontWeight: selected
                ? FontWeight.w600
                : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
