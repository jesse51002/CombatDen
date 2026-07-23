// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'growth_metric_data.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

KpiTile _$KpiTileFromJson(Map<String, dynamic> json) => KpiTile(
  key: json['key'] as String,
  label: json['label'] as String,
  value: (json['value'] as num).toDouble(),
  unit: MetricUnit.fromJson(json['unit'] as String),
  deltaPct: (json['delta_pct'] as num?)?.toDouble(),
  deltaAbs: (json['delta_abs'] as num?)?.toDouble(),
  compareLabel: json['compare_label'] as String?,
);

KpiGroupData _$KpiGroupDataFromJson(Map<String, dynamic> json) => KpiGroupData(
  tiles: (json['tiles'] as List<dynamic>)
      .map((e) => KpiTile.fromJson(e as Map<String, dynamic>))
      .toList(),
);

HeroSegment _$HeroSegmentFromJson(Map<String, dynamic> json) => HeroSegment(
  key: json['key'] as String,
  label: json['label'] as String,
  value: (json['value'] as num).toDouble(),
  tone: json['tone'] as String?,
);

HeroSplitData _$HeroSplitDataFromJson(Map<String, dynamic> json) =>
    HeroSplitData(
      total: (json['total'] as num).toDouble(),
      unit: MetricUnit.fromJson(json['unit'] as String),
      caption: json['caption'] as String?,
      segments: (json['segments'] as List<dynamic>)
          .map((e) => HeroSegment.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

SeriesPoint _$SeriesPointFromJson(Map<String, dynamic> json) => SeriesPoint(
  date: json['date'] as String,
  value: (json['value'] as num).toDouble(),
);

MetricSeries _$MetricSeriesFromJson(Map<String, dynamic> json) => MetricSeries(
  key: json['key'] as String,
  label: json['label'] as String,
  points: (json['points'] as List<dynamic>)
      .map((e) => SeriesPoint.fromJson(e as Map<String, dynamic>))
      .toList(),
);

ClassSeries _$ClassSeriesFromJson(Map<String, dynamic> json) => ClassSeries(
  classId: json['class_id'] as String,
  className: json['class_name'] as String,
  series: (json['series'] as List<dynamic>)
      .map((e) => MetricSeries.fromJson(e as Map<String, dynamic>))
      .toList(),
);

MetricTableColumn _$MetricTableColumnFromJson(Map<String, dynamic> json) =>
    MetricTableColumn(
      key: json['key'] as String,
      label: json['label'] as String,
      type: MemberListColumnType.fromJson(json['type'] as String),
      align: json['align'] as String?,
    );

MetricTableRow _$MetricTableRowFromJson(Map<String, dynamic> json) =>
    MetricTableRow(cells: _cellsFromJson(json['cells'] as List));

MetricTable _$MetricTableFromJson(Map<String, dynamic> json) => MetricTable(
  orientation: TableOrientation.fromJson(json['orientation'] as String),
  columns: (json['columns'] as List<dynamic>)
      .map((e) => MetricTableColumn.fromJson(e as Map<String, dynamic>))
      .toList(),
  rows: (json['rows'] as List<dynamic>)
      .map((e) => MetricTableRow.fromJson(e as Map<String, dynamic>))
      .toList(),
);

LineData _$LineDataFromJson(Map<String, dynamic> json) => LineData(
  unit: MetricUnit.fromJson(json['unit'] as String),
  granularity: json['granularity'] as String,
  series: (json['series'] as List<dynamic>)
      .map((e) => MetricSeries.fromJson(e as Map<String, dynamic>))
      .toList(),
  byClass: (json['by_class'] as List<dynamic>?)
      ?.map((e) => ClassSeries.fromJson(e as Map<String, dynamic>))
      .toList(),
  table: json['table'] == null
      ? null
      : MetricTable.fromJson(json['table'] as Map<String, dynamic>),
);

BarsData _$BarsDataFromJson(Map<String, dynamic> json) => BarsData(
  unit: MetricUnit.fromJson(json['unit'] as String),
  granularity: json['granularity'] as String,
  series: (json['series'] as List<dynamic>)
      .map((e) => MetricSeries.fromJson(e as Map<String, dynamic>))
      .toList(),
  byClass: (json['by_class'] as List<dynamic>?)
      ?.map((e) => ClassSeries.fromJson(e as Map<String, dynamic>))
      .toList(),
  table: json['table'] == null
      ? null
      : MetricTable.fromJson(json['table'] as Map<String, dynamic>),
);

BreakdownItem _$BreakdownItemFromJson(Map<String, dynamic> json) =>
    BreakdownItem(
      key: json['key'] as String,
      label: json['label'] as String,
      value: (json['value'] as num).toDouble(),
      colorHint: json['color_hint'] as String?,
    );

BreakdownData _$BreakdownDataFromJson(Map<String, dynamic> json) =>
    BreakdownData(
      unit: MetricUnit.fromJson(json['unit'] as String),
      items: (json['items'] as List<dynamic>)
          .map((e) => BreakdownItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

DonutSpec _$DonutSpecFromJson(Map<String, dynamic> json) => DonutSpec(
  key: json['key'] as String,
  label: json['label'] as String,
  pct: (json['pct'] as num).toDouble(),
  caption: json['caption'] as String?,
);

DonutPairData _$DonutPairDataFromJson(Map<String, dynamic> json) =>
    DonutPairData(
      donuts: (json['donuts'] as List<dynamic>)
          .map((e) => DonutSpec.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

ClassHeatmap _$ClassHeatmapFromJson(Map<String, dynamic> json) => ClassHeatmap(
  classId: json['class_id'] as String,
  className: json['class_name'] as String,
  cells: (json['cells'] as List<dynamic>)
      .map(
        (e) =>
            (e as List<dynamic>).map((e) => (e as num?)?.toDouble()).toList(),
      )
      .toList(),
);

HeatmapData _$HeatmapDataFromJson(Map<String, dynamic> json) => HeatmapData(
  unit: MetricUnit.fromJson(json['unit'] as String),
  rows: (json['rows'] as List<dynamic>).map((e) => e as String).toList(),
  cols: (json['cols'] as List<dynamic>).map((e) => e as String).toList(),
  cells: (json['cells'] as List<dynamic>)
      .map(
        (e) =>
            (e as List<dynamic>).map((e) => (e as num?)?.toDouble()).toList(),
      )
      .toList(),
  byClass: (json['by_class'] as List<dynamic>?)
      ?.map((e) => ClassHeatmap.fromJson(e as Map<String, dynamic>))
      .toList(),
);

MemberListColumn _$MemberListColumnFromJson(Map<String, dynamic> json) =>
    MemberListColumn(
      key: json['key'] as String,
      label: json['label'] as String,
      type: MemberListColumnType.fromJson(json['type'] as String),
      align: json['align'] as String?,
    );

MemberListRow _$MemberListRowFromJson(Map<String, dynamic> json) =>
    MemberListRow(
      memberId: json['member_id'] as String,
      cells: _cellsFromJson(json['cells'] as List),
    );

MemberListData _$MemberListDataFromJson(Map<String, dynamic> json) =>
    MemberListData(
      columns: (json['columns'] as List<dynamic>)
          .map((e) => MemberListColumn.fromJson(e as Map<String, dynamic>))
          .toList(),
      rows: (json['rows'] as List<dynamic>)
          .map((e) => MemberListRow.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
