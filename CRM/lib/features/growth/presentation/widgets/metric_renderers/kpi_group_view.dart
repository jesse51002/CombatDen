import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/growth/data/models/growth_metric_data.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/kpi_metric_tile.dart';
import 'package:crm/shared/widgets/empty_state.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// A strip carries at most this many tiles; past it the group is a grid
/// nobody reads.
const int kMaxKpiTiles = 6;

/// A lone tile takes a quarter of the row — full width it reads as a broken
/// hero rather than one stat among several.
const double _loneTileWidthFactor = 0.25;

/// Renders a `kpi_group` metric: N headline tiles on the page, separated by
/// thin rules. No cards — the figures sit directly on the ground.
class KpiGroupView extends StatelessWidget {
  final KpiGroupData data;
  final String metricKey;
  final String name;

  const KpiGroupView({
    super.key,
    required this.data,
    required this.metricKey,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    if (data.tiles.isEmpty) {
      return EmptyState.inline(
        icon: Symbols.bar_chart_sharp,
        title: 'No $name yet',
        body: 'These figures appear once the gym has recorded activity.',
        minHeight: DesignConstants.heroChartHeight / 2,
      );
    }
    if (data.tiles.length > kMaxKpiTiles) {
      log('KpiGroupView: "$metricKey" served ${data.tiles.length} tiles; '
          'rendering the first $kMaxKpiTiles');
    }
    final tiles = data.tiles.take(kMaxKpiTiles).toList();

    if (tiles.length == 1) {
      return Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: _loneTileWidthFactor,
          child: KpiMetricTile(tile: tiles.first),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Below the nav breakpoint the content owns the full width, and four
        // tiles across stop fitting: two per row.
        final perRow =
            constraints.maxWidth < DesignConstants.navMobileBreakpoint ? 2 : 4;
        return _TileRows(tiles: tiles, perRow: perRow);
      },
    );
  }
}

class _TileRows extends StatelessWidget {
  final List<KpiTile> tiles;
  final int perRow;

  const _TileRows({required this.tiles, required this.perRow});

  @override
  Widget build(BuildContext context) {
    final rows = <List<KpiTile>>[];
    for (var i = 0; i < tiles.length; i += perRow) {
      rows.add(
        tiles.sublist(i, (i + perRow).clamp(0, tiles.length)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Hairline(),
          _TileRow(tiles: rows[i]),
        ],
      ],
    );
  }
}

class _TileRow extends StatelessWidget {
  final List<KpiTile> tiles;

  const _TileRow({required this.tiles});

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[];
    for (var i = 0; i < tiles.length; i++) {
      if (i > 0) cells.add(const Hairline(vertical: true));
      cells.add(Expanded(child: KpiMetricTile(tile: tiles[i])));
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingBig,
        children: cells,
      ),
    );
  }
}
