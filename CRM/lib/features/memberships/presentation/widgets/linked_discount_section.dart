import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';

/// Per-plan linked (family) member discount editor: an enable
/// toggle and the price each additional linked member pays
/// (2nd / 3rd / 4th / 5th+), with a live running total.
class LinkedDiscountSection extends StatefulWidget {
  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;

  /// The plan's base price field (listened to for the totals).
  final TextEditingController priceController;

  /// Four controllers (dollars) for the 2nd, 3rd, 4th, 5th+ tiers.
  final List<TextEditingController> tierControllers;

  const LinkedDiscountSection({
    super.key,
    required this.enabled,
    required this.onEnabledChanged,
    required this.priceController,
    required this.tierControllers,
  });

  @override
  State<LinkedDiscountSection> createState() =>
      _LinkedDiscountSectionState();
}

class _LinkedDiscountSectionState extends State<LinkedDiscountSection> {
  static const _labels = [
    '2nd Member Price',
    '3rd Member Price',
    '4th Member Price',
    '5th+ Member Price',
  ];

  @override
  void initState() {
    super.initState();
    widget.priceController.addListener(_onChanged);
    for (final c in widget.tierControllers) {
      c.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.priceController.removeListener(_onChanged);
    for (final c in widget.tierControllers) {
      c.removeListener(_onChanged);
    }
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  double _dollars(TextEditingController c) =>
      double.tryParse(c.text.trim()) ?? 0;

  String _money(double d) => '\$${d.toStringAsFixed(0)}';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Row(
          children: [
            Text('Linked Discount', style: DesignConstants.h1),
            const Spacer(),
            _Toggle(
              enabled: widget.enabled,
              onChanged: widget.onEnabledChanged,
            ),
          ],
        ),
        if (widget.enabled) _tiers(),
      ],
    );
  }

  Widget _tiers() {
    final base = _dollars(widget.priceController);
    var runningParts = _money(base);
    var runningSum = base;
    final rows = <Widget>[];
    for (var i = 0; i < widget.tierControllers.length; i++) {
      final tier = _dollars(widget.tierControllers[i]);
      runningSum += tier;
      runningParts = '$runningParts + ${_money(tier)}';
      final isLast = i == widget.tierControllers.length - 1;
      rows.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingSmall,
          children: [
            CustomTextField(
              controller: widget.tierControllers[i],
              label: _labels[i],
              hintText: '0',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
            ),
            Text(
              'Total Membership: $runningParts = '
              '${_money(runningSum)}${isLast ? '+' : ''}',
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: rows,
    );
  }
}

class _Toggle extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _Toggle({required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        _Option(
          label: 'Discount Disabled',
          active: !enabled,
          onTap: () => onChanged(false),
        ),
        _Option(
          label: 'Discount Enabled',
          active: enabled,
          onTap: () => onChanged(true),
        ),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _Option({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.paddingSmall,
          vertical: DesignConstants.spacingSmall,
        ),
        decoration: BoxDecoration(
          color: active ? DesignConstants.primaryColor : null,
          border: Border.all(
            color: active
                ? DesignConstants.primaryColor
                : DesignConstants.line,
          ),
          borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        ),
        child: Text(
          label,
          style: DesignConstants.pSmall.copyWith(
            color: active ? DesignConstants.surface : DesignConstants.text2nd,
          ),
        ),
      ),
    );
  }
}
