import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/discount_duration_unit.dart';
import 'package:crm/features/member_details/data/models/discount_mode.dart';
import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/memberships/bloc/discounts/discounts_bloc.dart';
import 'package:crm/features/memberships/bloc/discounts/discounts_event.dart';
import 'package:crm/features/memberships/data/models/discount_create_request.dart';
import 'package:crm/features/memberships/data/models/discount_update_request.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';
import 'package:crm/shared/widgets/form/app_dropdown_field.dart';

enum _AmountKind { percentage, dollar }

/// How an `ongoing` discount ends: after a duration span, on an
/// explicit date, or never (forever).
enum _LifetimeKind { duration, untilDate, forever }

/// Create / edit a discount preset: name, a % or \$ amount, and a
/// once / ongoing lifetime (ongoing ends by a duration span, an
/// explicit end date, or forever). Editing a value mints a new
/// version on the backend; old versions stay as read-only history.
class EditDiscountDialog extends StatefulWidget {
  final DiscountsBloc bloc;
  final String gymId;
  final DiscountResponse? discount;

  const EditDiscountDialog({
    super.key,
    required this.bloc,
    required this.gymId,
    this.discount,
  });

  static Future<void> show({
    required BuildContext context,
    required DiscountsBloc bloc,
    required String gymId,
    DiscountResponse? discount,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) =>
          EditDiscountDialog(bloc: bloc, gymId: gymId, discount: discount),
    );
  }

  @override
  State<EditDiscountDialog> createState() => _EditDiscountDialogState();
}

class _EditDiscountDialogState extends State<EditDiscountDialog> {
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _durationController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  _AmountKind _kind = _AmountKind.percentage;
  DiscountMode _mode = DiscountMode.once;
  DiscountDurationUnit _durationUnit = DiscountDurationUnit.month;
  _LifetimeKind _lifetime = _LifetimeKind.duration;
  DateTime? _endDate;

  bool get _isEdit => widget.discount != null;

  @override
  void initState() {
    super.initState();
    final d = widget.discount;
    if (d != null) {
      _nameController.text = d.discountName;
      if (d.dollarOff != null) {
        _kind = _AmountKind.dollar;
        _amountController.text = (d.dollarOff! / 100).toStringAsFixed(2);
      } else if (d.percentageOff != null) {
        _kind = _AmountKind.percentage;
        _amountController.text = d.percentageOff!.toStringAsFixed(0);
      }
      _mode = d.discountMode == DiscountMode.unknown
          ? DiscountMode.once
          : d.discountMode;
      _durationUnit = d.durationUnit == null ||
              d.durationUnit == DiscountDurationUnit.unknown
          ? DiscountDurationUnit.month
          : d.durationUnit!;
      _durationController.text = (d.durationAmount ?? 1).toString();
      if (d.endDate != null) {
        _lifetime = _LifetimeKind.untilDate;
        _endDate = d.endDate;
      } else if (d.durationAmount != null) {
        _lifetime = _LifetimeKind.duration;
      } else {
        _lifetime = _LifetimeKind.forever;
      }
    } else {
      _durationController.text = '1';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  bool get _isOngoing => _mode == DiscountMode.ongoing;

  double? get _amount => double.tryParse(_amountController.text.trim());

  String? _validateName(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Enter a name' : null;

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
    return (n == null || n <= 0) ? 'Enter a number above 0' : null;
  }

  Future<void> _pickEndDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  Widget _endDateField() {
    final label = _endDate == null
        ? 'Pick a date'
        : DateFormat('MMM d, y').format(_endDate!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text('End date', style: DesignConstants.h2),
        InkWell(
          onTap: _pickEndDate,
          borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignConstants.paddingSmall,
              vertical: DesignConstants.paddingSmall,
            ),
            decoration: BoxDecoration(
              color: DesignConstants.card,
              borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
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
                    color: _endDate == null
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

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final name = _nameController.text.trim();
    final amount = _amount;
    if (amount == null) return;

    final percentageOff = _kind == _AmountKind.percentage ? amount : null;
    final dollarOff =
        _kind == _AmountKind.dollar ? (amount * 100).round() : null;
    int? durationAmount;
    DiscountDurationUnit? durationUnit;
    DateTime? endDate;
    if (_isOngoing) {
      switch (_lifetime) {
        case _LifetimeKind.duration:
          durationAmount = int.tryParse(_durationController.text.trim());
          durationUnit = _durationUnit;
        case _LifetimeKind.untilDate:
          if (_endDate == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Pick an end date.')),
            );
            return;
          }
          endDate = _endDate;
        case _LifetimeKind.forever:
          break;
      }
    }

    if (_isEdit) {
      widget.bloc.add(DiscountUpdated(DiscountUpdateRequest(
        discountId: widget.discount!.discountId,
        gymId: widget.gymId,
        identity: DiscountUpdateIdentity(discountName: name),
        values: DiscountUpdateValues(
          percentageOff: percentageOff,
          dollarOff: dollarOff,
          discountMode: _mode,
          durationAmount: durationAmount,
          durationUnit: durationUnit,
          endDate: endDate,
        ),
      )));
    } else {
      widget.bloc.add(DiscountCreated(DiscountCreateRequest(
        gymId: widget.gymId,
        discountName: name,
        percentageOff: percentageOff,
        dollarOff: dollarOff,
        discountMode: _mode,
        durationAmount: durationAmount,
        durationUnit: durationUnit,
        endDate: endDate,
      )));
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isEdit ? 'Discount saved.' : 'Discount created.',
          style: DesignConstants.p.copyWith(color: DesignConstants.surface),
        ),
        backgroundColor: DesignConstants.goodGreen,
      ),
    );
    Navigator.of(context).pop();
  }

  void _delete() {
    widget.bloc.add(DiscountDeleted(
      discountId: widget.discount!.discountId,
      gymId: widget.gymId,
    ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: _isEdit ? 'Edit Discount' : 'New Discount',
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingLarge,
          children: [
          CustomTextField(
            controller: _nameController,
            label: 'Name',
            hintText: 'New Year Discount',
            validator: _validateName,
          ),
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
                  onChanged: (v) => setState(() => _kind = v ?? _kind),
                ),
              ),
              Expanded(
                child: CustomTextField(
                  controller: _amountController,
                  label: _kind == _AmountKind.percentage
                      ? 'Percent'
                      : 'Amount (\$)',
                  hintText: _kind == _AmountKind.percentage ? '20' : '30',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
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
            onChanged: (v) => setState(() => _mode = v ?? _mode),
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
              onChanged: (v) => setState(() => _lifetime = v ?? _lifetime),
            ),
          if (_isOngoing && _lifetime == _LifetimeKind.untilDate)
            _endDateField(),
          if (_isOngoing && _lifetime == _LifetimeKind.duration)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DesignConstants.spacingMedium,
              children: [
                Expanded(
                  child: CustomTextField(
                    controller: _durationController,
                    label: 'For',
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    validator: _validateDuration,
                  ),
                ),
                Expanded(
                  child: AppDropdownField<DiscountDurationUnit>(
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
                        value: DiscountDurationUnit.month,
                        child: Text('Month'),
                      ),
                    ],
                    onChanged: (v) =>
                        setState(() => _durationUnit = v ?? _durationUnit),
                  ),
                ),
              ],
            ),
        ],
        ),
      ),
      actions: AppDialogActions(
        primaryLabel: _isEdit ? 'Save' : 'Create',
        primaryOnPressed: _save,
        secondaryLabel: 'Cancel',
        secondaryOnPressed: () => Navigator.of(context).pop(),
        destructiveLabel: _isEdit ? 'Delete' : null,
        destructiveOnPressed: _isEdit ? _delete : null,
      ),
    );
  }
}
