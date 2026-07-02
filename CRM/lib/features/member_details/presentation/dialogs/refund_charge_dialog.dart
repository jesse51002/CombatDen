import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/payment_record.dart';
import 'package:crm/features/member_details/presentation/widgets/member_detail_format.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';
import 'package:crm/shared/widgets/filter_pills.dart';

/// Refunds a prior [PaymentRecord] — full or partial. The
/// partial branch takes an amount (capped at the refundable
/// remainder) and dispatches [RefundChargeRequested] with it;
/// full leaves the amount null. The bloc reloads the member on
/// success and surfaces a failure via its `actionError` path.
class RefundChargeDialog extends StatefulWidget {
  final PaymentRecord charge;

  const RefundChargeDialog({super.key, required this.charge});

  /// Resolves to `true` once a refund is submitted (the bloc commit is
  /// dispatched), `null` when dismissed — so a caller can chain a
  /// follow-up (e.g. the one-time "also cancel?" prompt). Callers that only
  /// fire-and-forget can ignore the result.
  static Future<bool?> show({
    required BuildContext context,
    required PaymentRecord charge,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<MemberDetailBloc>(),
        child: RefundChargeDialog(charge: charge),
      ),
    );
  }

  @override
  State<RefundChargeDialog> createState() =>
      _RefundChargeDialogState();
}

class _RefundChargeDialogState extends State<RefundChargeDialog> {
  bool _partial = false;
  final TextEditingController _amount = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// The refundable balance — the charge minus anything
  /// already refunded. A full refund returns this remainder.
  int get _refundable => widget.charge.netAmount;

  String get _chargeLabel => formatMinorUnits(
        _refundable,
        currency: widget.charge.currency,
      );

  /// Parse the dollar input into minor units, or null when
  /// blank/invalid.
  int? _parseCents() {
    final raw = _amount.text.trim();
    if (raw.isEmpty) return null;
    final value = double.tryParse(raw);
    if (value == null) return null;
    return (value * 100).round();
  }

  void _submit() {
    int? amount;
    if (_partial) {
      final cents = _parseCents();
      if (cents == null || cents <= 0) {
        setState(() => _error = 'Enter an amount to refund.');
        return;
      }
      if (cents > _refundable) {
        setState(
          () => _error =
              'Cannot exceed the $_chargeLabel refundable.',
        );
        return;
      }
      amount = cents;
    }
    context.read<MemberDetailBloc>().add(
          RefundChargeRequested(
            chargeId: widget.charge.chargeId,
            amount: amount,
          ),
        );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Refund charge',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          Text(
            'Refund the $_chargeLabel charge from '
            '${formatDay(widget.charge.chargeTime)}.',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text,
            ),
          ),
          FilterPills(
            labels: const ['Full refund', 'Partial refund'],
            selectedIndex: _partial ? 1 : 0,
            onSelected: (i) => setState(() {
              _partial = i == 1;
              _error = null;
            }),
          ),
          if (_partial)
            CustomTextField(
              controller: _amount,
              label: 'Amount to refund',
              hintText: 'e.g. 25.00',
              keyboardType:
                  const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'[0-9.]'),
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
        primaryLabel: 'Refund',
        primaryColor: DesignConstants.badRed,
        primaryOnPressed: _submit,
        secondaryLabel: 'Cancel',
        secondaryOnPressed: () => Navigator.of(context).pop(),
      ),
    );
  }
}
