import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/linked_discount_value.dart';
import 'package:crm/features/memberships/presentation/widgets/icon_option_cards.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';

enum _AmountKind { percentage, dollar }

/// Per-plan linked (family) discount editor: an enable toggle, a short
/// explainer, a $-off / %-off type, and a dynamic list of family-member
/// tiers ("Add another person", capped at 5 members). The last tier is a
/// "+" catch-all (e.g. "5th+ member"). Each tier is a real discount value —
/// like a regular discount, not a "member price" — and a live family total is
/// rendered from the plan's base price.
class LinkedDiscountSection extends StatefulWidget {
  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;
  final List<LinkedDiscountValue> initialValues;
  final ValueChanged<List<LinkedDiscountValue>> onChanged;

  /// The plan's base price field (dollars) — drives the family total.
  final TextEditingController priceController;

  const LinkedDiscountSection({
    super.key,
    required this.enabled,
    required this.onEnabledChanged,
    required this.initialValues,
    required this.onChanged,
    required this.priceController,
  });

  @override
  State<LinkedDiscountSection> createState() => _LinkedDiscountSectionState();
}

class _LinkedDiscountSectionState extends State<LinkedDiscountSection> {
  // 2nd..5th member — a hard cap of 5 members on a membership.
  static const _maxTiers = 4;

  late _AmountKind _kind;
  late List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    final vals = widget.initialValues;
    _kind = vals.any((v) => v.dollarOff != null)
        ? _AmountKind.dollar
        : _AmountKind.percentage;
    _controllers =
        vals.isEmpty ? [_controller(null)] : [for (final v in vals) _controller(v)];
    for (final c in _controllers) {
      c.addListener(_onTierChanged);
    }
    widget.priceController.addListener(_refresh);
  }

  TextEditingController _controller(LinkedDiscountValue? v) {
    final text = v == null
        ? ''
        : v.percentageOff != null
            ? _fmt(v.percentageOff!)
            : ((v.dollarOff ?? 0) / 100).toStringAsFixed(2);
    return TextEditingController(text: text);
  }

  String _fmt(double d) =>
      d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toString();

  @override
  void dispose() {
    widget.priceController.removeListener(_refresh);
    for (final c in _controllers) {
      c.removeListener(_onTierChanged);
      c.dispose();
    }
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _onTierChanged() {
    _refresh();
    _emit();
  }

  void _emit() {
    final values = <LinkedDiscountValue>[];
    for (final c in _controllers) {
      final d = double.tryParse(c.text.trim());
      if (d == null || d <= 0) continue;
      values.add(
        _kind == _AmountKind.percentage
            ? LinkedDiscountValue(percentageOff: d)
            : LinkedDiscountValue(dollarOff: (d * 100).round()),
      );
    }
    widget.onChanged(values);
  }

  void _addTier() {
    if (_controllers.length >= _maxTiers) return;
    final c = TextEditingController()..addListener(_onTierChanged);
    setState(() => _controllers.add(c));
    _emit();
  }

  void _removeTier(int i) {
    final c = _controllers.removeAt(i);
    c.removeListener(_onTierChanged);
    c.dispose();
    setState(() {});
    _emit();
  }

  String? _validate(String? v) {
    final d = double.tryParse(v?.trim() ?? '');
    if (d == null) return 'Enter a value';
    if (_kind == _AmountKind.percentage) {
      if (d <= 0 || d > 100) return 'Percent must be 1–100';
    } else if (d <= 0) {
      return 'Must be above 0';
    }
    return null;
  }

  // What an additional member pays = base price minus that tier's discount.
  double _memberPrice(double base, TextEditingController c) {
    final d = double.tryParse(c.text.trim());
    if (d == null || d <= 0) return base;
    final price = _kind == _AmountKind.percentage
        ? base * (1 - d / 100)
        : base - d;
    return price.clamp(0.0, base);
  }

  String _money(double d) => '\$${d.toStringAsFixed(0)}';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Row(
          children: [
            Text('Linked (family) discount', style: DesignConstants.h1),
            const Spacer(),
            _Toggle(enabled: widget.enabled, onChanged: widget.onEnabledChanged),
          ],
        ),
        if (widget.enabled) _body(),
      ],
    );
  }

  Widget _body() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(
          'For when one person pays for several memberships — usually a '
          'family. The main member pays full price; each extra person you add '
          "gets the discount below, billed together on the payer's card.\n"
          'Example: a \$150/mo parent adds two kids at 20% off → \$150 + '
          '\$120 + \$120.',
          style: DesignConstants.pSmall.copyWith(color: DesignConstants.text2nd),
        ),
        IconOptionCards(
          options: const [
            IconOption(icon: Symbols.percent_sharp, label: '% off'),
            IconOption(icon: Symbols.attach_money_sharp, label: '\$ off'),
          ],
          selectedIndex: _kind == _AmountKind.percentage ? 0 : 1,
          onSelected: (i) {
            setState(
              () => _kind = i == 0 ? _AmountKind.percentage : _AmountKind.dollar,
            );
            _emit();
          },
        ),
        for (var i = 0; i < _controllers.length; i++) _tierRow(i),
        if (_controllers.length < _maxTiers)
          AppOutlineButton(
            text: 'Add another person',
            onPressed: _addTier,
            borderRadius: DesignConstants.radiusSmall,
            icon: Icon(
              Icons.add,
              size: DesignConstants.iconSizeSmall,
              color: DesignConstants.text,
            ),
          ),
        _totalLine(),
      ],
    );
  }

  Widget _tierRow(int i) {
    // The last tier is the "+" catch-all (it and every member beyond).
    final isLast = i == _controllers.length - 1;
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        Expanded(
          child: CustomTextField(
            controller: _controllers[i],
            label: '${_ordinal(i + 2)}${isLast ? '+' : ''} member',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            validator: _validate,
          ),
        ),
        if (_controllers.length > 1)
          IconButton(
            onPressed: () => _removeTier(i),
            icon: Icon(
              Symbols.close_sharp,
              size: DesignConstants.iconSizeMedium,
              weight: DesignConstants.iconWeight,
              color: DesignConstants.text2nd,
            ),
          ),
      ],
    );
  }

  Widget _totalLine() {
    final base = double.tryParse(widget.priceController.text.trim()) ?? 0;
    final parts = <double>[
      base,
      for (final c in _controllers) _memberPrice(base, c),
    ];
    final total = parts.fold<double>(0, (a, b) => a + b);
    // The last tier is a "+" catch-all, so the family total is open-ended.
    return Text(
      'Family total: ${parts.map(_money).join(' + ')} = ${_money(total)}+/mo',
      style: DesignConstants.pSmall.copyWith(color: DesignConstants.text),
    );
  }

  static String _ordinal(int n) {
    switch (n) {
      case 2:
        return '2nd';
      case 3:
        return '3rd';
      case 4:
        return '4th';
      default:
        return '5th';
    }
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
        _Option(label: 'Off', active: !enabled, onTap: () => onChanged(false)),
        _Option(label: 'On', active: enabled, onTap: () => onChanged(true)),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _Option({required this.label, required this.active, required this.onTap});

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
            color: active ? DesignConstants.primaryColor : DesignConstants.line,
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
