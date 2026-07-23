import 'package:flutter/material.dart';

import 'package:crm/features/growth/data/models/growth_metric.dart';
import 'package:crm/features/growth/data/models/growth_metric_data.dart';

/// Wide, scrollable host so a chart's fixed heights never overflow the test
/// viewport and a `LayoutBuilder` gets a realistic desktop width.
Widget host(Widget child) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(width: 900, child: child),
        ),
      ),
    );

final DateTime _computedAt = DateTime.utc(2026, 7, 20, 14);

GrowthMetric _envelope({
  required String key,
  required String name,
  required GrowthMetricType type,
  required GrowthMetricData data,
}) =>
    GrowthMetric(
      key: key,
      name: name,
      categories: const [GrowthCategory.overview],
      type: type,
      order: 10,
      computedAt: _computedAt,
      data: data,
    );

GrowthMetric kpiMetric({
  List<KpiTile>? tiles,
  String key = 'members_kpis',
  String name = 'Members',
}) =>
    _envelope(
      key: key,
      name: name,
      type: GrowthMetricType.kpiGroup,
      data: KpiGroupData(
        tiles: tiles ??
            const [
              KpiTile(
                key: 'total_members',
                label: 'Total members',
                value: 128,
                unit: MetricUnit.count,
                deltaPct: 11,
                compareLabel: 'vs 115 last month',
              ),
              KpiTile(
                key: 'churn',
                label: 'Churn',
                value: 9,
                unit: MetricUnit.percent,
                deltaPct: 4,
                compareLabel: 'vs 5% last month',
              ),
            ],
      ),
    );

GrowthMetric heroMetric({
  List<HeroSegment>? segments,
  double total = 914000,
  String key = 'revenue_hero',
  String name = 'Revenue',
}) =>
    _envelope(
      key: key,
      name: name,
      type: GrowthMetricType.heroSplit,
      data: HeroSplitData(
        total: total,
        unit: MetricUnit.cents,
        caption: 'Expected in July',
        segments: segments ??
            const [
              HeroSegment(
                key: 'collected',
                label: 'Collected',
                value: 792000,
                tone: 'accent',
              ),
              HeroSegment(
                key: 'expected',
                label: 'Expected',
                value: 102000,
                tone: 'neutral',
              ),
              HeroSegment(
                key: 'overdue',
                label: 'Overdue',
                value: 20000,
                tone: 'warn',
              ),
            ],
      ),
    );

List<MetricSeries> _twoSeries() => const [
      MetricSeries(
        key: 'checkins',
        label: 'Check-ins',
        points: [
          SeriesPoint(date: '2026-05-01', value: 120),
          SeriesPoint(date: '2026-06-01', value: 141),
          SeriesPoint(date: '2026-07-01', value: 133),
        ],
      ),
      MetricSeries(
        key: 'signups',
        label: 'Sign-ups',
        points: [
          SeriesPoint(date: '2026-05-01', value: 150),
          SeriesPoint(date: '2026-06-01', value: 160),
          SeriesPoint(date: '2026-07-01', value: 155),
        ],
      ),
    ];

GrowthMetric lineMetric({
  List<MetricSeries>? series,
  String key = 'members_trend',
  String name = 'Members trend',
}) =>
    _envelope(
      key: key,
      name: name,
      type: GrowthMetricType.line,
      data: LineData(
        unit: MetricUnit.count,
        granularity: 'month',
        series: series ?? _twoSeries(),
      ),
    );

GrowthMetric barsMetric({
  List<MetricSeries>? series,
  String key = 'signups_vs_checkins',
  String name = 'Sign-ups vs check-ins',
}) =>
    _envelope(
      key: key,
      name: name,
      type: GrowthMetricType.bars,
      data: BarsData(
        unit: MetricUnit.count,
        granularity: 'month',
        series: series ?? _twoSeries(),
      ),
    );

GrowthMetric breakdownMetric({
  List<BreakdownItem>? items,
  String key = 'members_by_plan',
  String name = 'Members by plan',
}) =>
    _envelope(
      key: key,
      name: name,
      type: GrowthMetricType.breakdown,
      data: BreakdownData(
        unit: MetricUnit.count,
        items: items ??
            const [
              BreakdownItem(key: 'unlimited', label: 'Unlimited', value: 64),
              BreakdownItem(key: 'twice', label: '2x / week', value: 31),
            ],
      ),
    );

GrowthMetric donutMetric({
  List<DonutSpec>? donuts,
  String key = 'churn_donuts',
  String name = 'Monthly churn',
}) =>
    _envelope(
      key: key,
      name: name,
      type: GrowthMetricType.donutPair,
      data: DonutPairData(
        donuts: donuts ??
            const [
              DonutSpec(
                key: 'last_30',
                label: 'Last 30 days',
                pct: 9,
                caption: 'Members lost',
              ),
              DonutSpec(key: 'gym_avg', label: 'Gym average', pct: 12),
            ],
      ),
    );

GrowthMetric heatmapMetric({
  List<String>? rows,
  List<String>? cols,
  List<List<double?>>? cells,
  String key = 'attendance_heatmap',
  String name = 'Busy times',
}) =>
    _envelope(
      key: key,
      name: name,
      type: GrowthMetricType.heatmap,
      data: HeatmapData(
        unit: MetricUnit.count,
        rows: rows ?? const ['Mon', 'Tue'],
        cols: cols ?? const ['6a', '8a', '10a'],
        cells: cells ??
            const [
              [4.0, 12.0, 0.0],
              [7.0, 9.0, 2.0],
            ],
      ),
    );

GrowthMetric memberListMetric({
  List<MemberListColumn>? columns,
  List<MemberListRow>? rows,
  String key = 'at_risk_members',
  String name = 'At-risk members',
}) =>
    _envelope(
      key: key,
      name: name,
      type: GrowthMetricType.memberList,
      data: MemberListData(
        columns: columns ??
            const [
              MemberListColumn(
                key: 'name',
                label: 'Member',
                type: MemberListColumnType.text,
              ),
              MemberListColumn(
                key: 'visits',
                label: 'Visits',
                type: MemberListColumnType.number,
              ),
            ],
        rows: rows ??
            const [
              MemberListRow(memberId: 'm-1', cells: ['Ana Reyes', 3.0]),
            ],
      ),
    );
