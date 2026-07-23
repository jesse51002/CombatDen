import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/growth/bloc/growth_bloc.dart';
import 'package:crm/features/growth/bloc/growth_event.dart';
import 'package:crm/features/growth/bloc/growth_state.dart';
import 'package:crm/features/growth/data/models/growth_metric.dart';
import 'package:crm/features/growth/data/models/growth_metric_data.dart';
import 'package:crm/features/growth/data/repositories/growth_repository.dart';
import 'package:crm/features/growth/presentation/widgets/growth_metric_registry.dart';
import 'package:crm/features/growth/presentation/widgets/growth_section.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/line_view.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// Recurring revenue over time — the `mrr_trend` line — as a self-contained
/// dashboard section beneath the money hero.
///
/// The Growth Revenue tab and the dashboard draw the SAME line off the same
/// `mrr_trend` metric, so the two never disagree. Self-contained like
/// [RevenueHeroCard]: it owns its repository + bloc, so the rest of the
/// dashboard stays stateless.
///
/// It renders the CHART ONLY — never the metric's companion table, even
/// though `mrr_trend` carries one on the Growth page; a dashboard card shows
/// the line, not a per-month breakdown.
///
/// It fails QUIETLY, exactly as [RevenueHeroCard] does: a spinner while
/// loading, and nothing at all (`SizedBox.shrink`) on error or when the
/// metric is absent, so the dashboard renders even when growth is
/// unreachable or has not computed yet. The Growth page owns the explanation.
class RevenueTrendCard extends StatelessWidget {
  const RevenueTrendCard({super.key});

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider<GrowthRepository>(
      create: (_) => GrowthRepository(apiClient: ApiClient()),
      child: BlocProvider<GrowthBloc>(
        create: (ctx) => GrowthBloc(
          repository: ctx.read<GrowthRepository>(),
        )..add(const GrowthLoadRequested()),
        child: const _RevenueTrendView(),
      ),
    );
  }
}

class _RevenueTrendView extends StatelessWidget {
  const _RevenueTrendView();

  /// The gym's recurring-revenue trend: the `mrr_trend` metric.
  GrowthMetric? _trendOf(GrowthState state) {
    for (final metric in state.metrics) {
      if (metric.key == 'mrr_trend') return metric;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GrowthBloc, GrowthState>(
      builder: (context, state) {
        switch (state.status) {
          case GrowthStatus.initial:
          case GrowthStatus.loading:
            return const SizedBox(
              height: DesignConstants.heroChartHeight,
              child: Center(
                child: AppSpinner(size: DesignConstants.spinnerSizeLarge),
              ),
            );
          case GrowthStatus.error:
            return const SizedBox.shrink();
          case GrowthStatus.loaded:
            final metric = _trendOf(state);
            final data = metric?.data;
            if (metric == null || data is! LineData) {
              return const SizedBox.shrink();
            }
            // The section title names the line; the renderer draws the chart
            // only (showCompanionTable: false), so a per-month table never
            // rides onto the dashboard.
            return GrowthSection(
              title: metric.name,
              subtitle: metricWindowLabel(metric.key),
              child: LineView(
                data: data,
                metricKey: metric.key,
                name: metric.name,
                showCompanionTable: false,
              ),
            );
        }
      },
    );
  }
}
