import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/discounts/custom_discount_form_value.dart';
import 'package:crm/features/membership_flow/discounts/discount_copy.dart';
import 'package:crm/features/membership_flow/discounts/flow_discount_end_date_field.dart';
import 'package:crm/features/membership_flow/discounts/flow_segmented.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_field_box.dart';

/// How long a custom discount lasts: the six lifetimes, then whichever ONE
/// field the chosen lifetime needs.
///
/// **Staff-only** — see `discount_labels.dart`.
///
/// The three branches are the backend's lifetime spec exactly — a duration
/// span, an explicit end date, or forever — and the widget renders exactly one
/// of them, which is what makes "never both" a property of the screen rather
/// than a rule the form has to remember.
class FlowDiscountLifetimeField extends StatelessWidget {
  final FlowDiscountLifetime lifetime;
  final ValueChanged<FlowDiscountLifetime> onLifetimeChanged;

  /// The span count, for the four span lifetimes.
  final TextEditingController spanController;

  /// The span's failed-validation line, or null. Set only after a failed Add.
  final String? spanError;

  final DateTime endDate;
  final ValueChanged<DateTime> onEndDateChanged;

  const FlowDiscountLifetimeField({
    super.key,
    required this.lifetime,
    required this.onLifetimeChanged,
    required this.spanController,
    required this.endDate,
    required this.onEndDateChanged,
    this.spanError,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingLarge,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingSmall,
          children: [
            Text(FlowDiscountCopy.lifetimeLabel, style: scale.label),
            Text(
              FlowDiscountCopy.lifetimeNote,
              style: scale.caption.copyWith(color: DesignConstants.text2nd),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: FlowSegmented<FlowDiscountLifetime>(
            options: FlowDiscountLifetime.values,
            value: lifetime,
            labelOf: (option) => option.label,
            onChanged: onLifetimeChanged,
            wrap: true,
          ),
        ),
        if (flowLifetimeNeedsSpan(lifetime))
          _SpanField(
            lifetime: lifetime,
            controller: spanController,
            errorText: spanError,
          )
        else if (lifetime == FlowDiscountLifetime.untilDate)
          FlowDiscountEndDateField(
            value: endDate,
            onChanged: onEndDateChanged,
          ),
      ],
    );
  }
}

/// The count beside a span lifetime, with its live reading underneath.
class _SpanField extends StatelessWidget {
  final FlowDiscountLifetime lifetime;
  final TextEditingController controller;
  final String? errorText;

  const _SpanField({
    required this.lifetime,
    required this.controller,
    this.errorText,
  });

  /// `3 cycles (3 months)` — a cycle is one plan billing cycle, which is a
  /// month for every recurring plan the catalogue sells, and staff quoting
  /// "three months" to a member need both readings. Calendar spans read
  /// plainly.
  String get _reading {
    final count = int.tryParse(controller.text.trim());
    if (count == null || count <= 0) return '';
    final word = lifetime.label.toLowerCase();
    final singular = word.substring(0, word.length - 1);
    final unit = count == 1 ? singular : word;
    if (lifetime != FlowDiscountLifetime.cycles) return '$count $unit';
    final months = count == 1 ? 'month' : 'months';
    return '$count $unit ($count $months)';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final reading = _reading;
        return FlowFieldBox(
          controller: controller,
          label: lifetime == FlowDiscountLifetime.cycles
              ? FlowDiscountCopy.cyclesLabel
              : FlowDiscountCopy.spanLabel,
          hintText: lifetime.label,
          icon: Symbols.autorenew_sharp,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          helperText: reading.isEmpty ? null : reading,
          errorText: errorText,
        );
      },
    );
  }
}
