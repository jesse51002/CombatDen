import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/discount_duration_unit.dart';
import 'package:crm/features/member_details/data/models/discount_mode.dart';
import 'package:crm/features/member_details/data/models/discount_value.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';
import 'package:crm/shared/widgets/form/app_dropdown_field.dart';

enum _AmountKind { percentage, dollar }

/// How an `ongoing` custom ends: after a duration span, on
/// an explicit date, or never.
enum _LifetimeKind { duration, untilDate, forever }

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

  _AmountKind _kind = _AmountKind.percentage;
  DiscountMode _mode = DiscountMode.once;
  DiscountDurationUnit _durationUnit =
      DiscountDurationUnit.month;
  _LifetimeKind _lifetime = _LifetimeKind.duration;
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

  String? _validateAmount(String? v) {
    final d = double.tryParse(v?.trim() ?? '');
    if (d == null) return 'Enter an amount';
    if (_kind == _AmountKind.percentage) {
      if (d <= 0 || d > 100) return 'Percent must be 1–100';
    } else if (d <= 0) {
      return 'Amount must be above 0';
    }
    return null;
  }

  String? _validateDuration(String? v) {
    final n = int.tryParse(v?.trim() ?? '');
    return (n == null || n <= 0)
        ? 'Enter a number above 0'
        : null;
  }

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
        _lifetime == _LifetimeKind.untilDate &&
        _endDate == null) {
      setState(() => _formError = 'Pick an end date.');
      return;
    }

    int? durationAmount;
    DiscountDurationUnit? durationUnit;
    DateTime? endDate;
    if (_isOngoing) {
      switch (_lifetime) {
        case _LifetimeKind.duration:
          durationAmount =
              int.tryParse(_durationController.text.trim());
          durationUnit = _durationUnit;
        case _LifetimeKind.untilDate:
          endDate = _endDate;
        case _LifetimeKind.forever:
          break;
      }
    }
    widget.onAdd(DiscountValue(
      percentageOff: _kind == _AmountKind.percentage
          ? amount
          : null,
      dollarOff: _kind == _AmountKind.dollar
          ? (amount * 100).round()
          : null,
      discountMode: _mode,
      durationAmount: durationAmount,
      durationUnit: durationUnit,
      endDate: endDate,
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingMedium,
            children: [
              Expanded(
                child: AppDropdownField<_AmountKind>(
                  label: 'Type',
                  value: _kind,
                  items: const [
                    DropdownMenuItem(
                      value: _AmountKind.percentage,
                      child: Text('% off'),
                    ),
                    DropdownMenuItem(
                      value: _AmountKind.dollar,
                      child: Text('\$ off'),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => _kind = v ?? _kind),
                ),
              ),
              Expanded(
                child: CustomTextField(
                  controller: _amountController,
                  label: _kind == _AmountKind.percentage
                      ? 'Percent'
                      : 'Amount (\$)',
                  hintText:
                      _kind == _AmountKind.percentage
                          ? '20'
                          : '30',
                  keyboardType: const TextInputType
                      .numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'[0-9.]'),
                    ),
                  ],
                  validator: _validateAmount,
                ),
              ),
            ],
          ),
          AppDropdownField<DiscountMode>(
            label: 'Applies',
            value: _mode,
            items: const [
              DropdownMenuItem(
                value: DiscountMode.once,
                child: Text('Once'),
              ),
              DropdownMenuItem(
                value: DiscountMode.ongoing,
                child: Text('Ongoing'),
              ),
            ],
            onChanged: (v) =>
                setState(() => _mode = v ?? _mode),
          ),
          if (_isOngoing)
            AppDropdownField<_LifetimeKind>(
              label: 'Lifetime',
              value: _lifetime,
              items: const [
                DropdownMenuItem(
                  value: _LifetimeKind.duration,
                  child: Text('For a duration'),
                ),
                DropdownMenuItem(
                  value: _LifetimeKind.untilDate,
                  child: Text('Until a date'),
                ),
                DropdownMenuItem(
                  value: _LifetimeKind.forever,
                  child: Text('Forever'),
                ),
              ],
              onChanged: (v) => setState(
                () => _lifetime = v ?? _lifetime,
              ),
            ),
          if (_isOngoing &&
              _lifetime == _LifetimeKind.duration)
            Row(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              spacing: DesignConstants.spacingMedium,
              children: [
                Expanded(
                  child: CustomTextField(
                    controller: _durationController,
                    label: 'For',
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter
                          .digitsOnly,
                    ],
                    validator: _validateDuration,
                  ),
                ),
                Expanded(
                  child: AppDropdownField<
                      DiscountDurationUnit>(
                    label: 'Unit',
                    value: _durationUnit,
                    items: const [
                      DropdownMenuItem(
                        value: DiscountDurationUnit.day,
                        child: Text('Day'),
                      ),
                      DropdownMenuItem(
                        value: DiscountDurationUnit.week,
                        child: Text('Week'),
                      ),
                      DropdownMenuItem(
                        value:
                            DiscountDurationUnit.month,
                        child: Text('Month'),
                      ),
                    ],
                    onChanged: (v) => setState(
                      () => _durationUnit =
                          v ?? _durationUnit,
                    ),
                  ),
                ),
              ],
            ),
          if (_isOngoing &&
              _lifetime == _LifetimeKind.untilDate)
            _EndDateField(
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

class _EndDateField extends StatelessWidget {
  final DateTime? endDate;
  final VoidCallback onTap;

  const _EndDateField({
    required this.endDate,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = endDate == null
        ? 'Pick a date'
        : DateFormat('MMM d, y').format(endDate!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text('End date', style: DesignConstants.h3),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(
            DesignConstants.radiusBig,
          ),
          child: Container(
            padding: const EdgeInsets.all(
              DesignConstants.paddingSmall,
            ),
            decoration: BoxDecoration(
              color: DesignConstants.card,
              borderRadius: BorderRadius.circular(
                DesignConstants.radiusBig,
              ),
              border: Border.all(
                color: DesignConstants.text,
                width: DesignConstants.buttonBorder,
              ),
            ),
            child: Row(
              spacing: DesignConstants.spacingMedium,
              children: [
                Icon(
                  Icons.calendar_today,
                  size: DesignConstants.iconSizeSmall,
                  color: DesignConstants.text2nd,
                ),
                Text(
                  label,
                  style: DesignConstants.p.copyWith(
                    color: endDate == null
                        ? DesignConstants.text3rd
                        : DesignConstants.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
