import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/discount_duration_unit.dart';
import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/member_details/data/models/discount_value.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/custom_discount_value_helpers.dart';
import 'package:crm/features/memberships/bloc/discounts/discounts_bloc.dart';
import 'package:crm/features/memberships/bloc/discounts/discounts_event.dart';
import 'package:crm/features/memberships/data/models/discount_create_request.dart';
import 'package:crm/features/memberships/data/models/discount_update_request.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';
import 'package:crm/shared/widgets/form/app_dropdown_field.dart';

enum _AmountKind { percentage, dollar }

/// Create / edit a discount preset: name, a % or \$ amount,
/// and a lifetime (Forever / Cycle / Day / Week / Month).
/// Cycle = 1 plan billing cycle — the replacement for the
/// removed `once` mode. Editing a value mints a new version
/// on the backend; old versions stay as read-only history.
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
  CustomDiscountLifetimeUnit _lifetimeUnit =
      CustomDiscountLifetimeUnit.cycle;
  DateTime? _endDate;

  bool get _isEdit => widget.discount != null;

  @override
  void initState() {
    super.initState();
    final d = widget.discount;
    if (d != null) {
      _nameController.text = d.discountName;
      final v = d.value;
      if (v.dollarOff != null) {
        _kind = _AmountKind.dollar;
        _amountController.text = (v.dollarOff! / 100).toStringAsFixed(2);
      } else if (v.percentageOff != null) {
        _kind = _AmountKind.percentage;
        _amountController.text = v.percentageOff!.toStringAsFixed(0);
      }
      // Resolve lifetime from the value's duration/end_date fields.
      if (v.endDate != null) {
        _lifetimeUnit = CustomDiscountLifetimeUnit.forever;
        _endDate = v.endDate;
      } else if (v.durationAmount != null && v.durationUnit != null) {
        _lifetimeUnit =
            _unitFromBackend(v.durationUnit!);
        _durationController.text = v.durationAmount!.toString();
      } else {
        _lifetimeUnit = CustomDiscountLifetimeUnit.forever;
      }
    } else {
      _durationController.text = '1';
    }
  }

  /// Maps a backend [DiscountDurationUnit] back to the UI
  /// [CustomDiscountLifetimeUnit].
  CustomDiscountLifetimeUnit _unitFromBackend(
    DiscountDurationUnit unit,
  ) {
    switch (unit) {
      case DiscountDurationUnit.cycle:
        return CustomDiscountLifetimeUnit.cycle;
      case DiscountDurationUnit.day:
        return CustomDiscountLifetimeUnit.day;
      case DiscountDurationUnit.week:
        return CustomDiscountLifetimeUnit.week;
      case DiscountDurationUnit.month:
        return CustomDiscountLifetimeUnit.month;
      case DiscountDurationUnit.unknown:
        return CustomDiscountLifetimeUnit.forever;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _durationController.dispose();
    super.dispose();
  }

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

  /// Builds a [DiscountValue] from the current form state.
  DiscountValue _buildValue() {
    final amount = _amount!;
    final percentageOff = _kind == _AmountKind.percentage ? amount : null;
    final dollarOff =
        _kind == _AmountKind.dollar ? (amount * 100).round() : null;

    int? durationAmount;
    DiscountDurationUnit? durationUnit;
    DateTime? endDate;

    // Until-date is a special case: the user selected Forever but picked a
    // date — the date was set from an existing value on edit.
    if (_endDate != null &&
        _lifetimeUnit == CustomDiscountLifetimeUnit.forever) {
      endDate = _endDate;
    } else {
      durationUnit = toDiscountDurationUnit(_lifetimeUnit);
      if (durationUnit != null) {
        durationAmount = int.tryParse(_durationController.text.trim());
      }
    }

    return DiscountValue(
      percentageOff: percentageOff,
      dollarOff: dollarOff,
      durationAmount: durationAmount,
      durationUnit: durationUnit,
      endDate: endDate,
    );
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final name = _nameController.text.trim();
    if (_amount == null) return;

    final discountValue = _buildValue();

    if (_isEdit) {
      widget.bloc.add(DiscountUpdated(DiscountUpdateRequest(
        discountId: widget.discount!.discountId,
        gymId: widget.gymId,
        identity: DiscountUpdateIdentity(discountName: name),
        value: discountValue,
      )));
    } else {
      widget.bloc.add(DiscountCreated(DiscountCreateRequest(
        gymId: widget.gymId,
        discountName: name,
        value: discountValue,
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

  bool get _showDurationField =>
      _lifetimeUnit != CustomDiscountLifetimeUnit.forever;

  String _durationFieldLabel() {
    switch (_lifetimeUnit) {
      case CustomDiscountLifetimeUnit.cycle:
        return 'Cycles';
      case CustomDiscountLifetimeUnit.day:
        return 'Days';
      case CustomDiscountLifetimeUnit.week:
        return 'Weeks';
      case CustomDiscountLifetimeUnit.month:
        return 'Months';
      case CustomDiscountLifetimeUnit.forever:
        return '';
    }
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
                    hintText:
                        _kind == _AmountKind.percentage ? '20' : '30',
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DesignConstants.spacingMedium,
              children: [
                Expanded(
                  child: AppDropdownField<CustomDiscountLifetimeUnit>(
                    label: 'Lifetime',
                    value: _lifetimeUnit,
                    items: CustomDiscountLifetimeUnit.values
                        .map(
                          (u) => DropdownMenuItem(
                            value: u,
                            child: Text(lifetimeUnitLabel(u)),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(
                      () => _lifetimeUnit = v ?? _lifetimeUnit,
                    ),
                  ),
                ),
                if (_showDurationField)
                  Expanded(
                    child: CustomTextField(
                      controller: _durationController,
                      label: _durationFieldLabel(),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      validator: _validateDuration,
                    ),
                  ),
              ],
            ),
            if (_lifetimeUnit == CustomDiscountLifetimeUnit.cycle)
              _CycleNote(controller: _durationController),
            if (_isEdit && _endDate != null &&
                _lifetimeUnit == CustomDiscountLifetimeUnit.forever)
              _endDateField(),
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

/// Parenthetical note below the Cycle amount field:
/// "N cycle(s) (N month(s))".
class _CycleNote extends StatelessWidget {
  final TextEditingController controller;

  const _CycleNote({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (_, _) {
        final n = int.tryParse(controller.text.trim()) ?? 1;
        final cycleWord = n == 1 ? 'cycle' : 'cycles';
        final monthWord = n == 1 ? 'month' : 'months';
        return Text(
          '$n $cycleWord ($n $monthWord)',
          style: DesignConstants.pSmall.copyWith(
            color: DesignConstants.text2nd,
          ),
        );
      },
    );
  }
}
