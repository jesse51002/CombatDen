import 'package:json_annotation/json_annotation.dart';

part 'growth_metric_data.g.dart';

/// How a metric's numeric values should be formatted.
///
/// Mirrors `MetricUnit` in
/// `FastApiBackend/src/growth/schema/growth_schema.py`.
@JsonEnum(valueField: 'value')
enum MetricUnit {
  count('count'),
  cents('cents'),
  percent('percent'),
  unknown('unknown');

  const MetricUnit(this.value);

  /// The snake_case value used in JSON serialization.
  final String value;

  /// Falls back to [unknown] so a new backend unit never crashes the page.
  static MetricUnit fromJson(String value) => MetricUnit.values.firstWhere(
        (v) => v.value == value,
        orElse: () => MetricUnit.unknown,
      );

  String toJson() => value;
}

/// How one `member_list` column's cells should be rendered.
///
/// Mirrors `MemberListColumnType` in the growth schema.
@JsonEnum(valueField: 'value')
enum MemberListColumnType {
  text('text'),
  number('number'),
  cents('cents'),
  date('date'),
  unknown('unknown');

  const MemberListColumnType(this.value);

  /// The snake_case value used in JSON serialization.
  final String value;

  /// Falls back to [unknown]; a renderer treats it as plain text.
  static MemberListColumnType fromJson(String value) =>
      MemberListColumnType.values.firstWhere(
        (v) => v.value == value,
        orElse: () => MemberListColumnType.unknown,
      );

  String toJson() => value;
}

/// The payload of one growth metric.
///
/// One subtype per `GrowthMetricType`, each mirroring the matching `*Data`
/// Pydantic model. Sealed so a renderer can switch exhaustively over the
/// eight shapes.
sealed class GrowthMetricData {
  const GrowthMetricData();
}

// ── kpi_group ──

/// One headline number inside a [KpiGroupData].
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class KpiTile {
  final String key;
  final String label;
  final double value;
  @JsonKey(fromJson: MetricUnit.fromJson)
  final MetricUnit unit;
  final double? deltaPct;
  final double? deltaAbs;
  final String? compareLabel;

  const KpiTile({
    required this.key,
    required this.label,
    required this.value,
    required this.unit,
    this.deltaPct,
    this.deltaAbs,
    this.compareLabel,
  });

  factory KpiTile.fromJson(Map<String, dynamic> json) =>
      _$KpiTileFromJson(json);
}

/// Payload for `kpi_group` — a row of headline tiles.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class KpiGroupData extends GrowthMetricData {
  final List<KpiTile> tiles;

  const KpiGroupData({required this.tiles});

  factory KpiGroupData.fromJson(Map<String, dynamic> json) =>
      _$KpiGroupDataFromJson(json);
}

// ── hero_split ──

/// One slice of a [HeroSplitData] total.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class HeroSegment {
  final String key;
  final String label;
  final double value;
  final String? tone;

  const HeroSegment({
    required this.key,
    required this.label,
    required this.value,
    this.tone,
  });

  factory HeroSegment.fromJson(Map<String, dynamic> json) =>
      _$HeroSegmentFromJson(json);
}

/// Payload for `hero_split` — one big total broken into segments.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class HeroSplitData extends GrowthMetricData {
  final double total;
  @JsonKey(fromJson: MetricUnit.fromJson)
  final MetricUnit unit;
  final String? caption;
  final List<HeroSegment> segments;

  const HeroSplitData({
    required this.total,
    required this.unit,
    this.caption,
    required this.segments,
  });

  factory HeroSplitData.fromJson(Map<String, dynamic> json) =>
      _$HeroSplitDataFromJson(json);
}

// ── line / bars (shared series shapes) ──

/// One (date, value) sample.
///
/// [date] is an ISO date STRING, not a `DateTime`: the payload round-trips
/// through jsonb, which has no date type.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class SeriesPoint {
  final String date;
  final double value;

  const SeriesPoint({required this.date, required this.value});

  factory SeriesPoint.fromJson(Map<String, dynamic> json) =>
      _$SeriesPointFromJson(json);
}

/// A named run of points inside a [LineData] / [BarsData] payload.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class MetricSeries {
  final String key;
  final String label;
  final List<SeriesPoint> points;

  const MetricSeries({
    required this.key,
    required this.label,
    required this.points,
  });

  factory MetricSeries.fromJson(Map<String, dynamic> json) =>
      _$MetricSeriesFromJson(json);
}

/// The same series set, restricted to a single class.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class ClassSeries {
  final String classId;
  final String className;
  final List<MetricSeries> series;

  const ClassSeries({
    required this.classId,
    required this.className,
    required this.series,
  });

  factory ClassSeries.fromJson(Map<String, dynamic> json) =>
      _$ClassSeriesFromJson(json);
}

// ── companion table (line / bars) ──

/// Where a metric's companion [MetricTable] sits relative to its chart.
///
/// Mirrors `TableOrientation` in the growth schema. Resilient: an unknown
/// value falls back to [unknown], which the renderer treats as [stacked].
@JsonEnum(valueField: 'value')
enum TableOrientation {
  stacked('stacked'),
  beside('beside'),
  unknown('unknown');

  const TableOrientation(this.value);

  /// The snake_case value used in JSON serialization.
  final String value;

  static TableOrientation fromJson(String value) =>
      TableOrientation.values.firstWhere(
        (v) => v.value == value,
        orElse: () => TableOrientation.unknown,
      );

  String toJson() => value;
}

/// One column header of a metric's companion [MetricTable].
///
/// Reuses [MemberListColumnType] — a cell renders by its column's declared
/// type exactly as a `member_list` cell does.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class MetricTableColumn {
  final String key;
  final String label;
  @JsonKey(fromJson: MemberListColumnType.fromJson)
  final MemberListColumnType type;
  final String? align;

  const MetricTableColumn({
    required this.key,
    required this.label,
    required this.type,
    this.align,
  });

  factory MetricTableColumn.fromJson(Map<String, dynamic> json) =>
      _$MetricTableColumnFromJson(json);
}

/// One companion-table row; [cells] is positional against
/// [MetricTable.columns], each a `String`, a `double`, or null — the same
/// normalisation [MemberListRow] uses.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class MetricTableRow {
  @JsonKey(fromJson: _cellsFromJson)
  final List<Object?> cells;

  const MetricTableRow({required this.cells});

  factory MetricTableRow.fromJson(Map<String, dynamic> json) =>
      _$MetricTableRowFromJson(json);
}

/// A data table rendered alongside a `line` / `bars` chart — under it
/// ([TableOrientation.stacked]) or beside it ([TableOrientation.beside]).
///
/// Mirrors `MetricTable` in the growth schema.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class MetricTable {
  @JsonKey(fromJson: TableOrientation.fromJson)
  final TableOrientation orientation;
  final List<MetricTableColumn> columns;
  final List<MetricTableRow> rows;

  const MetricTable({
    required this.orientation,
    required this.columns,
    required this.rows,
  });

  factory MetricTable.fromJson(Map<String, dynamic> json) =>
      _$MetricTableFromJson(json);
}

/// Payload for `line` — one or more time series drawn as lines.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class LineData extends GrowthMetricData {
  @JsonKey(fromJson: MetricUnit.fromJson)
  final MetricUnit unit;
  final String granularity;
  final List<MetricSeries> series;
  final List<ClassSeries>? byClass;

  /// An optional companion data table rendered alongside the chart (e.g. a
  /// per-month breakdown under the line). Null when the metric has no table.
  final MetricTable? table;

  const LineData({
    required this.unit,
    required this.granularity,
    required this.series,
    this.byClass,
    this.table,
  });

  factory LineData.fromJson(Map<String, dynamic> json) =>
      _$LineDataFromJson(json);
}

/// Payload for `bars` — one or more time series drawn as bars.
///
/// Structurally identical to [LineData] but declared separately: the two
/// renderers evolve independently, and an alias would couple them.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class BarsData extends GrowthMetricData {
  @JsonKey(fromJson: MetricUnit.fromJson)
  final MetricUnit unit;
  final String granularity;
  final List<MetricSeries> series;
  final List<ClassSeries>? byClass;

  /// The same optional companion data table [LineData] carries.
  final MetricTable? table;

  const BarsData({
    required this.unit,
    required this.granularity,
    required this.series,
    this.byClass,
    this.table,
  });

  factory BarsData.fromJson(Map<String, dynamic> json) =>
      _$BarsDataFromJson(json);
}

// ── breakdown ──

/// One labelled slice of a [BreakdownData].
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class BreakdownItem {
  final String key;
  final String label;
  final double value;
  final String? colorHint;

  const BreakdownItem({
    required this.key,
    required this.label,
    required this.value,
    this.colorHint,
  });

  factory BreakdownItem.fromJson(Map<String, dynamic> json) =>
      _$BreakdownItemFromJson(json);
}

/// Payload for `breakdown` — a ranked list of labelled values.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class BreakdownData extends GrowthMetricData {
  @JsonKey(fromJson: MetricUnit.fromJson)
  final MetricUnit unit;
  final List<BreakdownItem> items;

  const BreakdownData({required this.unit, required this.items});

  factory BreakdownData.fromJson(Map<String, dynamic> json) =>
      _$BreakdownDataFromJson(json);
}

// ── donut_pair ──

/// One donut in a [DonutPairData]; [pct] is a 0-100 percentage.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class DonutSpec {
  final String key;
  final String label;
  final double pct;
  final String? caption;

  const DonutSpec({
    required this.key,
    required this.label,
    required this.pct,
    this.caption,
  });

  factory DonutSpec.fromJson(Map<String, dynamic> json) =>
      _$DonutSpecFromJson(json);
}

/// Payload for `donut_pair` — side-by-side percentage donuts.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class DonutPairData extends GrowthMetricData {
  final List<DonutSpec> donuts;

  const DonutPairData({required this.donuts});

  factory DonutPairData.fromJson(Map<String, dynamic> json) =>
      _$DonutPairDataFromJson(json);
}

// ── heatmap ──

/// The same heatmap grid, restricted to a single class.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class ClassHeatmap {
  final String classId;
  final String className;

  /// A null cell is UNKNOWN, never zero — see [HeatmapData.cells].
  final List<List<double?>> cells;

  const ClassHeatmap({
    required this.classId,
    required this.className,
    required this.cells,
  });

  factory ClassHeatmap.fromJson(Map<String, dynamic> json) =>
      _$ClassHeatmapFromJson(json);
}

/// Payload for `heatmap` — a [rows] x [cols] grid of values.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class HeatmapData extends GrowthMetricData {
  @JsonKey(fromJson: MetricUnit.fromJson)
  final MetricUnit unit;
  final List<String> rows;
  final List<String> cols;

  /// The grid, row-major against [rows] / [cols].
  ///
  /// A cell is null when the value is genuinely UNKNOWN rather than zero — a
  /// cohort too young to have reached that age, say. The distinction is
  /// load-bearing: rendering an immature cohort as 0% would read as total
  /// churn. A renderer must draw null as an ABSENT cell, never as the bottom
  /// of the scale, and must never coerce it to 0.
  final List<List<double?>> cells;

  final List<ClassHeatmap>? byClass;

  const HeatmapData({
    required this.unit,
    required this.rows,
    required this.cols,
    required this.cells,
    this.byClass,
  });

  factory HeatmapData.fromJson(Map<String, dynamic> json) =>
      _$HeatmapDataFromJson(json);
}

// ── member_list ──

/// One column header of a [MemberListData].
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class MemberListColumn {
  final String key;
  final String label;
  @JsonKey(fromJson: MemberListColumnType.fromJson)
  final MemberListColumnType type;
  final String? align;

  const MemberListColumn({
    required this.key,
    required this.label,
    required this.type,
    this.align,
  });

  factory MemberListColumn.fromJson(Map<String, dynamic> json) =>
      _$MemberListColumnFromJson(json);
}

/// One member row; [cells] is positional against [MemberListData.columns].
///
/// [memberId] is carried separately so a row can deep-link to the member
/// detail page without a magic cell index.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class MemberListRow {
  final String memberId;

  /// Heterogeneous positional cells — each is a `String`, a `double`, or
  /// null, matching the column at the same index. JSON whole numbers are
  /// normalised to `double` so a renderer never has to handle `int`.
  @JsonKey(fromJson: _cellsFromJson)
  final List<Object?> cells;

  const MemberListRow({required this.memberId, required this.cells});

  factory MemberListRow.fromJson(Map<String, dynamic> json) =>
      _$MemberListRowFromJson(json);
}

/// Payload for `member_list` — a small tabular list of members.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class MemberListData extends GrowthMetricData {
  final List<MemberListColumn> columns;
  final List<MemberListRow> rows;

  const MemberListData({required this.columns, required this.rows});

  factory MemberListData.fromJson(Map<String, dynamic> json) =>
      _$MemberListDataFromJson(json);
}

List<Object?> _cellsFromJson(List<dynamic> json) =>
    json.map(_cellFromJson).toList(growable: false);

Object? _cellFromJson(Object? cell) {
  if (cell == null || cell is String) return cell;
  if (cell is num) return cell.toDouble();
  throw FormatException(
    'member_list cell must be a string, a number or null; '
    'got ${cell.runtimeType}',
  );
}
