import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/discount_duration_unit.dart';
import 'package:crm/features/member_details/data/models/discount_mode.dart';
import 'package:crm/features/member_details/data/models/discount_value.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/custom_discount_amount_fields.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/custom_discount_duration_fields.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/custom_discount_end_date_field.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/custom_discount_mode_fields.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/custom_discount_value_helpers.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';

/// Inline form producing one custom [DiscountValue] for a
/// membership draft: a % XOR $ amount, once / ongoing, and
/// an optional lifetime (duration span XOR end date).
/// Mirrors the value half of the preset editor
/// (`edit_discount_dialog.dart`) — customs have no name and
/// are minted server-side as one-shot `custom` discounts.
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
  DiscountMode _mode = DiscountMode.once;
  DiscountDurationUnit _durationUnit =
      DiscountDurationUnit.month;
  CustomDiscountLifetimeKind _lifetime =
      CustomDiscountLifetimeKind.duration;
  DateTime? _endDate;
  String? _formError;

  @override
  void dispose() {
    _amountController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  bool get _isOngoing => _mode == DiscountMode.ongoing;

  double? get _amount =>
      double.tryParse(_amountController.text.trim());

  Future<void> _pickEndDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _endDate ?? now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  void _add() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final amount = _amount;
    if (amount == null) return;
    if (_isOngoing &&
        _lifetime == CustomDiscountLifetimeKind.untilDate &&
        _endDate == null) {
      setState(() => _formError = 'Pick an end date.');
      return;
    }
    widget.onAdd(buildCustomDiscountValue(
      kind: _kind,
      amount: amount,
      mode: _mode,
      lifetime: _lifetime,
      durationText: _durationController.text,
      durationUnit: _durationUnit,
      endDate: _endDate,
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
          CustomDiscountModeFields(
            mode: _mode,
            lifetime: _lifetime,
            onModeChanged: (v) =>
                setState(() => _mode = v ?? _mode),
            onLifetimeChanged: (v) => setState(
              () => _lifetime = v ?? _lifetime,
            ),
          ),
          if (_isOngoing &&
              _lifetime ==
                  CustomDiscountLifetimeKind.duration)
            CustomDiscountDurationFields(
              controller: _durationController,
              unit: _durationUnit,
              onUnitChanged: (v) => setState(
                () => _durationUnit = v ?? _durationUnit,
              ),
            ),
          if (_isOngoing &&
              _lifetime ==
                  CustomDiscountLifetimeKind.untilDate)
            CustomDiscountEndDateField(
              endDate: _endDate,
              onTap: _pickEndDate,
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
