import 'package:equatable/equatable.dart';

import 'package:crm/features/growth/data/models/growth_metric.dart';

enum GrowthStatus { initial, loading, loaded, error }

/// State for the Growth page.
///
/// Holds every metric the backend served and this build can render, plus the
/// staleness floor ([computedAt]) shown alongside them. Metrics the CRM
/// cannot render were already dropped during parsing, so anything here is
/// safe to hand to a renderer.
class GrowthState extends Equatable {
  final GrowthStatus status;

  /// Every renderable metric, in the order the backend served them.
  final List<GrowthMetric> metrics;

  /// The oldest surviving metric's compute time; null when nothing has been
  /// computed for this gym yet.
  final DateTime? computedAt;

  /// User-facing failure message; set only when [status] is
  /// [GrowthStatus.error].
  final String? error;

  const GrowthState({
    this.status = GrowthStatus.initial,
    this.metrics = const [],
    this.computedAt,
    this.error,
  });

  /// True when the page loaded fine but the gym has no computed metrics yet
  /// (a brand-new gym before the first scheduled compute).
  ///
  /// Distinct from [GrowthStatus.error]: nothing is broken, there is just
  /// nothing to show — the UI shows a "not computed yet" note, not a retry.
  bool get isNotComputedYet =>
      status == GrowthStatus.loaded && computedAt == null && metrics.isEmpty;

  /// The metrics tagged with [category], ordered by [GrowthMetric.order].
  ///
  /// The server already sorts the whole list, but each tab renders its own
  /// filtered slice — this is that slice.
  List<GrowthMetric> metricsIn(GrowthCategory category) {
    final slice =
        metrics.where((m) => m.categories.contains(category)).toList();
    slice.sort((a, b) => a.order.compareTo(b.order));
    return slice;
  }

  GrowthState copyWith({
    GrowthStatus? status,
    List<GrowthMetric>? metrics,
    DateTime? computedAt,
    String? error,
    bool clearError = false,
  }) => GrowthState(
    status: status ?? this.status,
    metrics: metrics ?? this.metrics,
    computedAt: computedAt ?? this.computedAt,
    error: clearError ? null : error ?? this.error,
  );

  @override
  List<Object?> get props => [status, metrics, computedAt, error];
}
