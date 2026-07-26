import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/discount_value.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/discounts/custom_discount_form_value.dart';
import 'package:crm/features/membership_flow/discounts/discount_copy.dart';
import 'package:crm/features/membership_flow/discounts/flow_discount_end_date_field.dart';
import 'package:crm/features/membership_flow/discounts/flow_discount_lifetime_field.dart';
import 'package:crm/features/membership_flow/discounts/flow_segmented.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_buttons.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_field_box.dart';

/// A one-off discount built for THIS membership: what comes off, and how long
/// it lasts.
///
/// **Staff-only** — see `discount_labels.dart`.
///
/// It hands back a [DiscountValue] and nothing else. The value is the wire
/// contract — a `custom` discount is minted server-side from it at the money
/// step — so the form never invents an id, a name or a scope.
///
/// **Validation appears only after a failed Add.** A form that turns red on
/// the third keystroke of `12.5` is arguing with somebody still typing, and
/// staff filling this in have a member standing in front of them. The rule is
/// stated up front by the note beside the buttons, so a quiet form is not read
/// as a form with nothing to say.
class FlowCustomDiscountForm extends StatefulWidget {
  final ValueChanged<DiscountValue> onAdd;
  final VoidCallback onCancel;

  const FlowCustomDiscountForm({
    super.key,
    required this.onAdd,
    required this.onCancel,
  });

  @override
  State<FlowCustomDiscountForm> createState() => _FlowCustomDiscountFormState();
}

class _FlowCustomDiscountFormState extends State<FlowCustomDiscountForm> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _span = TextEditingController(text: '1');

  FlowDiscountAmountKind _kind = FlowDiscountAmountKind.percentage;
  FlowDiscountLifetime _lifetime = FlowDiscountLifetime.forever;

  /// Never empty, so the end-date branch has no "pick a date" failure to
  /// report — see [FlowDiscountEndDateField].
  DateTime _endDate = flowDefaultDiscountEndDate();

  /// Null until Add has been pressed and refused.
  String? _amountError;
  String? _spanError;

  @override
  void dispose() {
    _amount.dispose();
    _span.dispose();
    super.dispose();
  }

  /// Clearing the errors on a CHANGE is the other half of "validation appears
  /// only after a failed Add": once the answer moves, the complaint about the
  /// old one is stale.
  void _change(VoidCallback apply) {
    setState(() {
      apply();
      _amountError = null;
      _spanError = null;
    });
  }

  void _add() {
    final amountError = validateFlowDiscountAmount(_amount.text, _kind);
    final spanError = flowLifetimeNeedsSpan(_lifetime)
        ? validateFlowDiscountSpan(_span.text)
        : null;
    if (amountError != null || spanError != null) {
      setState(() {
        _amountError = amountError;
        _spanError = spanError;
      });
      return;
    }
    widget.onAdd(
      buildFlowDiscountValue(
        kind: _kind,
        amount: double.parse(_amount.text.trim()),
        lifetime: _lifetime,
        spanText: _span.text,
        endDate: _endDate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingBig,
      children: [
        _AmountRow(
          kind: _kind,
          controller: _amount,
          errorText: _amountError,
          onKindChanged: (kind) => _change(() => _kind = kind),
        ),
        FlowDiscountLifetimeField(
          lifetime: _lifetime,
          onLifetimeChanged: (value) => _change(() => _lifetime = value),
          spanController: _span,
          spanError: _spanError,
          endDate: _endDate,
          onEndDateChanged: (value) => _change(() => _endDate = value),
        ),
        _Actions(onCancel: widget.onCancel, onAdd: _add),
      ],
    );
  }
}

/// What comes off: the % XOR $ choice, then the number.
///
/// One row, because they are one answer — "12.5" means nothing without the
/// segment beside it, and splitting them onto two rows invites reading the
/// number alone.
class _AmountRow extends StatelessWidget {
  final FlowDiscountAmountKind kind;
  final TextEditingController controller;
  final String? errorText;
  final ValueChanged<FlowDiscountAmountKind> onKindChanged;

  const _AmountRow({
    required this.kind,
    required this.controller,
    required this.onKindChanged,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final percent = kind == FlowDiscountAmountKind.percentage;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingMedium,
          children: [
            Text(FlowDiscountCopy.amountKindLabel, style: scale.label),
            FlowSegmented<FlowDiscountAmountKind>(
              options: FlowDiscountAmountKind.values,
              value: kind,
              labelOf: (option) => option.label,
              onChanged: onKindChanged,
            ),
          ],
        ),
        Expanded(
          child: FlowFieldBox(
            controller: controller,
            label: FlowDiscountCopy.amountLabel,
            hintText: kind.label,
            icon: percent ? Symbols.percent_sharp : Symbols.payments_sharp,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            helperText: percent ? FlowDiscountCopy.percentHint : null,
            errorText: errorText,
          ),
        ),
      ],
    );
  }
}

/// The form's two decisions, with the validation rule stated beside them.
class _Actions extends StatelessWidget {
  final VoidCallback onCancel;
  final VoidCallback onAdd;

  const _Actions({required this.onCancel, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    return Row(
      spacing: DesignConstants.spacingLarge,
      children: [
        Expanded(
          child: Text(
            FlowDiscountCopy.validationNote,
            style: scale.caption.copyWith(color: DesignConstants.text2nd),
          ),
        ),
        FlowOutlineButton(
          text: FlowDiscountCopy.cancel,
          onPressed: onCancel,
        ),
        FlowPrimaryButton(
          text: FlowDiscountCopy.add,
          onPressed: onAdd,
        ),
      ],
    );
  }
}
