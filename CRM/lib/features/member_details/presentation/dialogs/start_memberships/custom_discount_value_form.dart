import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/discount_value.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/custom_discount_amount_fields.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/custom_discount_lifetime_fields.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/custom_discount_value_helpers.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';

/// Inline form producing one custom [DiscountValue] for a
/// membership draft: a % XOR $ amount and a lifetime
/// (Forever / Cycle / Day / Week / Month). Cycle = 1 plan
/// billing cycle (the former `once` mode). Mirrors the
/// value half of the preset editor
/// (`edit_discount_dialog.dart`).
class CustomDiscountValueForm extends StatefulWidget {
  final ValueChanged<DiscountValue> onAdd;
  final VoidCallback onCancel;

  const CustomDiscountValueForm({
    super.key,
    required this.onAdd,
    required this.onCancel,
  });

  @override
  State<CustomDiscountValueForm> createState() =>
      _CustomDiscountValueFormState();
}

class _CustomDiscountValueFormState
    extends State<CustomDiscountValueForm> {
  final _amountController = TextEditingController();
  final _durationController =
      TextEditingController(text: '1');
  final _formKey = GlobalKey<FormState>();

  CustomDiscountAmountKind _kind =
      CustomDiscountAmountKind.percentage;
  CustomDiscountLifetimeUnit _lifetimeUnit =
      CustomDiscountLifetimeUnit.cycle;
  String? _formError;

  @override
  void dispose() {
    _amountController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  double? get _amount =>
      double.tryParse(_amountController.text.trim());

  void _add() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final amount = _amount;
    if (amount == null) return;
    setState(() => _formError = null);
    widget.onAdd(buildCustomDiscountValue(
      kind: _kind,
      amount: amount,
      lifetimeUnit: _lifetimeUnit,
      durationText: _durationController.text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingMedium,
        children: [
          CustomDiscountAmountFields(
            kind: _kind,
            controller: _amountController,
            onKindChanged: (v) =>
                setState(() => _kind = v ?? _kind),
          ),
          CustomDiscountLifetimeFields(
            lifetimeUnit: _lifetimeUnit,
            durationController: _durationController,
            onUnitChanged: (v) => setState(
              () => _lifetimeUnit = v ?? _lifetimeUnit,
            ),
          ),
          if (_formError != null)
            Text(
              _formError!,
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.badRed,
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            spacing: DesignConstants.spacingMedium,
            children: [
              AppOutlineButton(
                text: 'Cancel',
                onPressed: widget.onCancel,
                borderRadius:
                    DesignConstants.radiusSmall,
              ),
              AppPrimaryButton(
                text: 'Add discount',
                onPressed: _add,
                borderRadius:
                    DesignConstants.radiusSmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
