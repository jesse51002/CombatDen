import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/growth/data/models/growth_metric_data.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/chrome/chart_readout_card.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/chrome/heat_scale_legend.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/format/metric_value_format.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/painters/heat_grid_geometry.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/painters/heat_grid_painter.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/series/drawn_series.dart';
import 'package:crm/shared/widgets/empty_state.dart';

/// Metrics whose grid prints the value inside each cell. Everything else is
/// an unlabelled density grid ("busy times").
const Set<String> kLabelledHeatmaps = {'cohort_retention'};

/// Renders a `heatmap` metric as a grid of density-filled cells.
///
/// **A null cell means NOT KNOWABLE YET** — a cohort too young to have
/// reached that age — and is drawn as an absent cell, never as the bottom of
/// the colour scale. Painting it as zero would tell an owner they lost every
/// member of that cohort.
class HeatmapView extends StatefulWidget {
  final HeatmapData data;
  final String metricKey;
  final String name;

  /// The selected class chip, when the metric carries `by_class`.
  final String? classId;

  const HeatmapView({
    super.key,
    required this.data,
    required this.metricKey,
    required this.name,
    this.classId,
  });

  @override
  State<HeatmapView> createState() => _HeatmapViewState();
}

class _HeatmapViewState extends State<HeatmapView> {
  (int, int)? _hovered;

  bool get _labelled => kLabelledHeatmaps.contains(widget.metricKey);

  TextStyle get _rowLabelStyle => _labelled
      ? DesignConstants.h3
      : DesignConstants.pSmall.copyWith(color: DesignConstants.text3rd);

  TextStyle get _colLabelStyle =>
      DesignConstants.pSmall.copyWith(color: DesignConstants.text3rd);

  @override
  Widget build(BuildContext context) {
    final cells = cellsForClass(
      widget.data.cells,
      widget.data.byClass,
      widget.classId,
    );
    final max = _maxOf(cells);
    if (widget.data.rows.isEmpty || _isBlank(cells)) {
      return EmptyState.inline(
        icon: Symbols.grid_view_sharp,
        title: 'No ${widget.name} yet',
        body: 'The grid fills in as check-ins are recorded.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        if (!_labelled) const HeatScaleLegend(),
        LayoutBuilder(
          builder: (context, constraints) {
            final geometry = _labelled
                ? HeatGridGeometry.cohort(
                    rows: widget.data.rows.length,
                    cols: widget.data.cols.length,
                  )
                : HeatGridGeometry.busy(
                    rows: widget.data.rows.length,
                    cols: widget.data.cols.length,
                    availableWidth: constraints.maxWidth,
                    rowLabelWidth: _rowLabelWidth(),
                  );
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _Grid(
                geometry: geometry,
                cells: cells,
                max: max,
                labelled: _labelled,
                unit: widget.data.unit,
                rows: widget.data.rows,
                cols: widget.data.cols,
                rowLabelStyle: _rowLabelStyle,
                colLabelStyle: _colLabelStyle,
                hovered: _hovered,
                onHover: (cell) {
                  if (cell != _hovered) setState(() => _hovered = cell);
                },
                semanticsLabel: widget.name,
              ),
            );
          },
        ),
      ],
    );
  }

  /// The gutter the row labels need, measured off the widest one.
  double _rowLabelWidth() {
    var widest = 0.0;
    for (final label in widget.data.rows) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: _rowLabelStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      if (painter.width > widest) widest = painter.width;
    }
    return widest + DesignConstants.spacingMedium;
  }

  static double _maxOf(List<List<double?>> cells) {
    var max = 0.0;
    for (final row in cells) {
      for (final cell in row) {
        if (cell != null && cell > max) max = cell;
      }
    }
    return max;
  }

  /// True when nothing has been recorded at all — every cell is null or 0.
  static bool _isBlank(List<List<double?>> cells) {
    for (final row in cells) {
      for (final cell in row) {
        if (cell != null && cell != 0) return false;
      }
    }
    return true;
  }
}

class _Grid extends StatelessWidget {
  final HeatGridGeometry geometry;
  final List<List<double?>> cells;
  final double max;
  final bool labelled;
  final MetricUnit unit;
  final List<String> rows;
  final List<String> cols;
  final TextStyle rowLabelStyle;
  final TextStyle colLabelStyle;
  final (int, int)? hovered;
  final ValueChanged<(int, int)?> onHover;
  final String semanticsLabel;

  const _Grid({
    required this.geometry,
    required this.cells,
    required this.max,
    required this.labelled,
    required this.unit,
    required this.rows,
    required this.cols,
    required this.rowLabelStyle,
    required this.colLabelStyle,
    required this.hovered,
    required this.onHover,
    required this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final size = geometry.size;
    return MouseRegion(
      // The hit-test walks the SAME geometry the painter laid the cells out
      // with, so the pointer always resolves the cell under it.
      onHover: (event) => onHover(geometry.hitTest(event.localPosition)),
      onExit: (_) => onHover(null),
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: Stack(
          children: [
            Positioned.fill(
              child: Semantics(
                label: semanticsLabel,
                child: CustomPaint(
                  painter: HeatGridPainter(
                    geometry: geometry,
                    cells: cells,
                    rowLabels: rows,
                    colLabels: cols,
                    maxValue: max,
                    labelled: labelled,
                    formatValue: (value) => formatMetricValue(value, unit),
                    outlineColor: DesignConstants.line,
                    absentFill: DesignConstants.backgroundAlt,
                    rowLabelStyle: rowLabelStyle,
                    colLabelStyle: colLabelStyle,
                    cellLabelStyle: DesignConstants.pSmallSemibold,
                    pendingStyle: DesignConstants.pSmall.copyWith(
                      color: DesignConstants.text3rd,
                    ),
                  ),
                ),
              ),
            ),
            if (hovered != null) _readout(size),
          ],
        ),
      ),
    );
  }

  Widget _readout(Size size) {
    final (row, col) = hovered!;
    final rect = geometry.cellRect(row, col);
    final value = row < cells.length && col < cells[row].length
        ? cells[row][col]
        : null;
    final left = (rect.center.dx - ChartReadoutCard.maxWidth / 2).clamp(
      0.0,
      (size.width - ChartReadoutCard.maxWidth).clamp(0.0, size.width),
    );
    return Positioned(
      left: left,
      top: rect.top,
      child: IgnorePointer(
        child: ChartReadoutCard(
          readout: ChartReadout(
            title: '${_labelAt(rows, row)} · ${_labelAt(cols, col)}',
            lines: [
              ChartReadoutLine(
                label: value == null ? 'Not recorded yet' : 'Value',
                // A null cell is unknown, not zero — the read-out says so
                // rather than printing a number nobody measured.
                value: value == null ? '—' : formatMetricValue(value, unit),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _labelAt(List<String> labels, int index) =>
      index < labels.length ? labels[index] : '';
}
