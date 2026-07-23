import 'package:crm/features/growth/data/models/growth_metric.dart';

/// How wide a metric's section renders.
enum MetricSpan { full, half }

/// Each metric's own measurement window, shown as the section subtitle.
///
/// The envelope carries no `window_label`, so it lives here, keyed by
/// metric `key`. An unknown key gets no subtitle rather than a wrong one —
/// a new backend metric still renders complete, just without a window line.
const Map<String, String> kMetricWindowLabels = {
  // Headline stat rows compare the current month against the one before.
  'members_kpis': 'This month vs last',
  'revenue_kpis': 'This month vs last',
  'revenue_quality_kpis': 'This month vs last',
  'attendance_kpis': 'This month vs last',
  'trial_kpis': 'This month vs last',
  'retention_kpis': 'This month vs last',
  'engagement_kpis': 'This month vs last',
  // Current-state snapshots.
  'revenue_hero': 'This month',
  'members_by_plan': 'Current',
  'membership_status_mix': 'Current',
  'member_tenure': 'Current',
  'revenue_by_plan': 'Current',
  'rank_distribution': 'Current',
  'class_fill_rate': 'Current',
  'trial_outcomes': 'Last 90 days',
  'active_trials': 'Current',
  'at_risk_members': 'Current',
  // Monthly histories.
  'members_trend': 'Monthly, all-time',
  'members_gained_lost': 'Monthly, all-time',
  'mrr_trend': 'Monthly, all-time',
  'revenue_collected': 'Monthly, all-time',
  'churn_trend': 'Monthly, all-time',
  'trials_started_vs_converted': 'Monthly, all-time',
  'trial_conversion_trend': 'Monthly, all-time',
  'promotions_trend': 'Monthly, all-time',
  'redemptions_trend': 'Monthly, all-time',
  'cohort_retention': 'Monthly, all-time',
  // Weekly histories.
  'checkins_trend': 'Weekly, all-time',
  'signups_vs_checkins': 'Weekly, all-time',
  'attendance_by_class': 'Weekly, all-time',
  'video_engagement': 'Weekly, all-time',
  // Rolling windows.
  'trial_engagement': 'Last 30 days',
  'attendance_heatmap': 'Last 90 days',
};

/// The window subtitle for [key], or the empty string when unknown.
String metricWindowLabel(String key) => kMetricWindowLabels[key] ?? '';

/// Span overrides, keyed by metric `key`. Everything not listed falls back
/// to the per-type default in [metricSpan].
const Map<String, MetricSpan> kMetricSpanOverrides = {
  // Plan breakdowns run long enough to need the full width.
  'members_by_plan': MetricSpan.full,
  'revenue_by_plan': MetricSpan.full,
  // Small companion charts that read fine side by side.
  'promotions_trend': MetricSpan.half,
  'redemptions_trend': MetricSpan.half,
  'cohort_retention': MetricSpan.half,
};

/// How wide [metric] renders: its override, else its type's default.
///
/// Only `breakdown` halves by default — it is the one payload whose rows
/// stay legible at half width.
MetricSpan metricSpan(GrowthMetric metric) =>
    kMetricSpanOverrides[metric.key] ??
    (metric.type == GrowthMetricType.breakdown
        ? MetricSpan.half
        : MetricSpan.full);
