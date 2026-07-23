import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/growth/data/models/growth_metric_data.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/format/metric_value_format.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/kpi_registry.dart';

/// One headline number: its label and glyph, the figure, a toned delta
/// badge, and the comparison it was measured against.
class KpiMetricTile extends StatelessWidget {
  final KpiTile tile;

  const KpiMetricTile({super.key, required this.tile});

  bool get _hasValue => !tile.value.isNaN && !tile.value.isInfinite;

  @override
  Widget build(BuildContext context) {
    final caption = _hasValue
        ? tile.compareLabel
        // A tile with no figure says why, instead of showing a bare dash.
        : 'Not enough data yet';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        _TitleRow(label: tile.label, icon: kpiIconFor(tile.key)),
        Row(
          spacing: DesignConstants.spacingMedium,
          children: [
            Flexible(
              child: Text(
                _hasValue ? formatMetricValue(tile.value, tile.unit) : '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _hasValue
                    ? DesignConstants.big2Light
                    : DesignConstants.big2Light.copyWith(
                        color: DesignConstants.text3rd,
                      ),
              ),
            ),
            if (_hasValue) _DeltaBadge(tile: tile),
          ],
        ),
        if (caption != null)
          Text(
            caption,
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
      ],
    );
  }
}

class _TitleRow extends StatelessWidget {
  final String label;
  final IconData icon;

  const _TitleRow({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: DesignConstants.spacingSmall,
      children: [
        Expanded(child: Text(label, style: DesignConstants.h2)),
        Icon(
          icon,
          size: DesignConstants.iconSizeMedium,
          weight: DesignConstants.iconWeight,
          color: DesignConstants.text2nd,
        ),
      ],
    );
  }
}

/// The movement badge — a direction arrow plus a toned figure.
///
/// Tone and arrow together carry the meaning: colour alone would fail for a
/// red/green-blind reader, and an uncoloured badge (the shape this replaces)
/// made `+11%` and `-20%` read identically.
class _DeltaBadge extends StatelessWidget {
  final KpiTile tile;

  const _DeltaBadge({required this.tile});

  @override
  Widget build(BuildContext context) {
    final delta = tile.deltaPct ?? tile.deltaAbs;
    final good = isGoodMove(tile.key, delta);
    if (delta == null || good == null) return const SizedBox.shrink();

    final tone = good ? DesignConstants.goodGreen : DesignConstants.badRed;
    final label = tile.deltaPct != null
        ? formatDeltaPct(tile.deltaPct!)
        : formatDeltaAbs(tile.deltaAbs!, tile.unit);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingMedium,
        vertical: DesignConstants.spacingSmall,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.backgroundAlt,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingSmall,
        children: [
          Icon(
            delta > 0
                ? Symbols.arrow_upward_sharp
                : Symbols.arrow_downward_sharp,
            size: DesignConstants.iconSizeTiny,
            weight: DesignConstants.iconWeight,
            color: tone,
          ),
          Text(
            label,
            style: DesignConstants.pSmallSemibold.copyWith(color: tone),
          ),
        ],
      ),
    );
  }
}
