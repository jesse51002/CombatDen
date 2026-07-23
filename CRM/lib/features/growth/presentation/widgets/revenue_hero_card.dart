import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/growth/bloc/growth_bloc.dart';
import 'package:crm/features/growth/bloc/growth_event.dart';
import 'package:crm/features/growth/bloc/growth_state.dart';
import 'package:crm/features/growth/data/models/growth_metric.dart';
import 'package:crm/features/growth/data/repositories/growth_repository.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/growth_metric_view.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// The money half-pie — collected / expected / overdue for the month — as
/// a self-contained dashboard section.
///
/// The Growth Overview tab and the dashboard show the SAME figure off the
/// same `revenue_hero` metric, so the two never disagree. Self-contained
/// like the Overdue / Upcoming cards: it owns its repository + bloc, so
/// the rest of the dashboard stays stateless.
///
/// It fails QUIETLY. The dashboard is the first screen after login and
/// must render even when growth is unreachable or has not computed yet,
/// so an error or a missing metric renders nothing at all rather than an
/// alarm the owner cannot act on. The Growth page owns the explanation.
class RevenueHeroCard extends StatelessWidget {
  const RevenueHeroCard({super.key});

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider<GrowthRepository>(
      create: (_) => GrowthRepository(apiClient: ApiClient()),
      child: BlocProvider<GrowthBloc>(
        create: (ctx) => GrowthBloc(
          repository: ctx.read<GrowthRepository>(),
        )..add(const GrowthLoadRequested()),
        child: const _RevenueHeroView(),
      ),
    );
  }
}

class _RevenueHeroView extends StatelessWidget {
  const _RevenueHeroView();

  /// The gym's money hero: the `revenue_hero` metric, or — if the backend
  /// ever renames it — the first `hero_split` served.
  GrowthMetric? _heroOf(GrowthState state) {
    GrowthMetric? fallback;
    for (final metric in state.metrics) {
      if (metric.key == 'revenue_hero') return metric;
      fallback ??= metric.type == GrowthMetricType.heroSplit ? metric : null;
    }
    return fallback;
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
            final hero = _heroOf(state);
            if (hero == null) return const SizedBox.shrink();
            return GrowthMetricView(metric: hero);
        }
      },
    );
  }
}
