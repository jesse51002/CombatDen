import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// One stat in the KPI strip on Growth — title + icon at the top,
/// big number with delta badge, then a "vs N last month" caption.
/// No card chrome: the strip separates stats with thin vertical rules.
class KpiTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final String value;
  final String deltaLabel;
  final String comparisonLabel;

  const KpiTile({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    required this.deltaLabel,
    required this.comparisonLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        _Title(label: label, icon: icon),
        _ValueRow(value: value, deltaLabel: deltaLabel),
        Text(
          comparisonLabel,
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
      ],
    );
  }
}

class _Title extends StatelessWidget {
  final String label;
  final IconData icon;
  const _Title({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: DesignConstants.h2,
          ),
        ),
        Icon(
          icon,
          weight: DesignConstants.iconWeight,
          color: DesignConstants.text2nd,
        ),
      ],
    );
  }
}

class _ValueRow extends StatelessWidget {
  final String value;
  final String deltaLabel;
  const _ValueRow({required this.value, required this.deltaLabel});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(
          value,
          style: DesignConstants.big2Light,
        ),
        _DeltaBadge(label: deltaLabel),
      ],
    );
  }
}

class _DeltaBadge extends StatelessWidget {
  final String label;
  const _DeltaBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingMedium,
        vertical: DesignConstants.spacingSmall,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.primaryColor25,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      ),
      child: Text(
        label,
        style: DesignConstants.pSmall.copyWith(
          color: DesignConstants.text,
        ),
      ),
    );
  }
}

/// Picks the matching `Symbols.*_sharp` icon from the data layer's plain
/// `IconData`. Mock data uses Material `Icons.*` constants as a stand-in
/// so the API surface stays plain Dart; this maps them to the real
/// `Symbols.*_sharp` glyphs the design system uses.
IconData kpiSymbolFor(IconData fallback) {
  if (fallback == Icons.group) return Symbols.group_sharp;
  if (fallback == Icons.card_giftcard) return Symbols.featured_seasonal_and_gifts_sharp;
  if (fallback == Icons.trending_up) return Symbols.trending_up_sharp;
  if (fallback == Icons.trending_down) return Symbols.trending_down_sharp;
  return Symbols.bar_chart_sharp;
}
