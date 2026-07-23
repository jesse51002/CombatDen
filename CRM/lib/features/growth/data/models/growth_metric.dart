import 'dart:developer';

import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/growth/data/models/growth_metric_data.dart';

part 'growth_metric.g.dart';

/// The renderer a metric's payload is drawn with.
///
/// Mirrors `GrowthMetricType` in
/// `FastApiBackend/src/growth/schema/growth_schema.py`.
@JsonEnum(valueField: 'value')
enum GrowthMetricType {
  kpiGroup('kpi_group'),
  heroSplit('hero_split'),
  line('line'),
  bars('bars'),
  breakdown('breakdown'),
  donutPair('donut_pair'),
  heatmap('heatmap'),
  memberList('member_list'),
  unknown('unknown');

  const GrowthMetricType(this.value);

  /// The snake_case value used in JSON serialization.
  final String value;

  /// Falls back to [unknown] for a type this build cannot draw; the metric is
  /// then skipped by [GrowthPage.fromJson] instead of crashing the page.
  static GrowthMetricType fromJson(String value) =>
      GrowthMetricType.values.firstWhere(
        (v) => v.value == value,
        orElse: () => GrowthMetricType.unknown,
      );

  String toJson() => value;
}

/// The Growth-page tab(s) a metric appears under.
///
/// Mirrors `GrowthCategory` in the growth schema.
@JsonEnum(valueField: 'value')
enum GrowthCategory {
  overview('overview'),
  members('members'),
  revenue('revenue'),
  attendance('attendance'),
  trial('trial'),
  retention('retention'),
  unknown('unknown');

  const GrowthCategory(this.value);

  /// The snake_case value used in JSON serialization.
  final String value;

  /// Falls back to [unknown], which no tab filters on — a metric tagged with
  /// a category this build doesn't know simply doesn't show under it.
  static GrowthCategory fromJson(String value) =>
      GrowthCategory.values.firstWhere(
        (v) => v.value == value,
        orElse: () => GrowthCategory.unknown,
      );

  static List<GrowthCategory> listFromJson(List<dynamic> json) => json
      .map((e) => e is String ? fromJson(e) : GrowthCategory.unknown)
      .toList(growable: false);

  String toJson() => value;
}

/// One served metric: registry-owned display metadata + its typed payload.
///
/// Mirrors `GrowthMetric` in the growth schema. [data] is resolved to the
/// model matching [type]; an unknown type or a payload that does not fit its
/// model throws, and [GrowthPage.fromJson] drops that one metric.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class GrowthMetric {
  final String key;
  final String name;
  @JsonKey(fromJson: GrowthCategory.listFromJson)
  final List<GrowthCategory> categories;
  @JsonKey(fromJson: GrowthMetricType.fromJson)
  final GrowthMetricType type;
  final int order;
  final DateTime computedAt;

  /// The payload, parsed into the model [type] names.
  ///
  /// The dispatch needs the sibling `type` field, so `readValue` hands the
  /// whole metric object to [_dataFromJson] rather than just `data`.
  @JsonKey(readValue: _readWholeMetric, fromJson: _dataFromJson)
  final GrowthMetricData data;

  const GrowthMetric({
    required this.key,
    required this.name,
    required this.categories,
    required this.type,
    required this.order,
    required this.computedAt,
    required this.data,
  });

  factory GrowthMetric.fromJson(Map<String, dynamic> json) =>
      _$GrowthMetricFromJson(json);
}

/// The whole Growth page for one gym.
///
/// Mirrors `GrowthResponse`. [computedAt] is the oldest surviving metric's
/// compute time (the staleness floor shown in the UI), or null when nothing
/// has been computed for this gym yet.
class GrowthPage {
  final DateTime? computedAt;
  final List<GrowthMetric> metrics;

  const GrowthPage({required this.computedAt, required this.metrics});

  /// Parses the response, SKIPPING every metric this build cannot render.
  ///
  /// The backend already omits metrics it cannot serve; the CRM mirrors that
  /// on its side. A metric with an unrecognised `type`, or whose `data` does
  /// not fit its type's model, is logged and dropped — its neighbours still
  /// render. One bad metric must never blank the page.
  ///
  /// A response with no `metrics` array at all is a different failure and
  /// does throw, so the bloc can show a retryable error.
  factory GrowthPage.fromJson(Map<String, dynamic> json) {
    final raw = json['metrics'];
    if (raw is! List) {
      throw const FormatException('growth response has no metrics array');
    }
    final metrics = <GrowthMetric>[];
    for (final entry in raw) {
      if (entry is! Map) {
        log('GrowthPage: skipping non-object metric entry');
        continue;
      }
      final map = Map<String, dynamic>.from(entry);
      try {
        metrics.add(GrowthMetric.fromJson(map));
      } catch (e, st) {
        log(
          'GrowthPage: skipping unrenderable metric "${map['key']}"',
          error: e,
          stackTrace: st,
        );
      }
    }
    final computedAt = json['computed_at'];
    return GrowthPage(
      computedAt: computedAt is String ? DateTime.tryParse(computedAt) : null,
      metrics: metrics,
    );
  }
}

/// `readValue` hook: hands the WHOLE metric object to [_dataFromJson] so the
/// payload dispatch can read the sibling `type` field.
Object? _readWholeMetric(Map<dynamic, dynamic> json, String key) => json;

GrowthMetricData _dataFromJson(Object? json) {
  final metric = Map<String, dynamic>.from(json! as Map);
  final rawType = metric['type'];
  final type = rawType is String
      ? GrowthMetricType.fromJson(rawType)
      : GrowthMetricType.unknown;
  final payload = metric['data'];
  if (payload is! Map) {
    throw FormatException(
      'growth metric "${metric['key']}" has no data object',
    );
  }
  final data = Map<String, dynamic>.from(payload);
  return switch (type) {
    GrowthMetricType.kpiGroup => KpiGroupData.fromJson(data),
    GrowthMetricType.heroSplit => HeroSplitData.fromJson(data),
    GrowthMetricType.line => LineData.fromJson(data),
    GrowthMetricType.bars => BarsData.fromJson(data),
    GrowthMetricType.breakdown => BreakdownData.fromJson(data),
    GrowthMetricType.donutPair => DonutPairData.fromJson(data),
    GrowthMetricType.heatmap => HeatmapData.fromJson(data),
    GrowthMetricType.memberList => MemberListData.fromJson(data),
    GrowthMetricType.unknown => throw FormatException(
        'growth metric "${metric['key']}" has unknown type "$rawType"',
      ),
  };
}
