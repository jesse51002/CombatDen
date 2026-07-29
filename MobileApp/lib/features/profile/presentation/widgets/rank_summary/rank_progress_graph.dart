import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/profile/bloc/rank_progress_bloc.dart';
import 'package:mobile_app/features/profile/bloc/rank_progress_event.dart';
import 'package:mobile_app/features/profile/bloc/rank_progress_state.dart';
import 'package:mobile_app/features/profile/data/models/rank_progress_point.dart';
import 'package:mobile_app/features/profile/data/rank_progress_selectors.dart';
import 'package:mobile_app/features/profile/presentation/widgets/rank_summary/rating_graph.dart';
import 'package:mobile_app/features/profile/presentation/widgets/rank_summary/timeframe_selector.dart';

// The graph's fixed footprint (shared by the plot, loading, and error states so
// the layout never jumps) — a per-screen layout ratio, not a design token.
const double _kGraphAspect = 393 / 196.5;

/// The rank graph + its timeframe selector, driven by [RankProgressBloc]. Holds
/// the selected timeframe as local UI state and windows the series client-side;
/// loading / retryable-error / empty all render inside the graph's footprint.
class RankProgressGraph extends StatefulWidget {
  const RankProgressGraph({super.key});

  @override
  State<RankProgressGraph> createState() => _RankProgressGraphState();
}

class _RankProgressGraphState extends State<RankProgressGraph> {
  RankTimeframe _timeframe = RankTimeframe.all;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RankProgressBloc, RankProgressState>(
      builder: (context, state) {
        switch (state.status) {
          case RankProgressStatus.initial:
          case RankProgressStatus.loading:
            return const _GraphBox(
              child: Center(child: CircularProgressIndicator()),
            );
          case RankProgressStatus.error:
            return _GraphError(
              message: state.errorMessage ?? 'Couldn\'t load rank progress.',
              onRetry: () => context
                  .read<RankProgressBloc>()
                  .add(const RankProgressLoadRequested()),
            );
          case RankProgressStatus.loaded:
            return _LoadedGraph(
              points: state.points,
              timeframe: _timeframe,
              onTimeframe: (tf) => setState(() => _timeframe = tf),
            );
        }
      },
    );
  }
}

class _LoadedGraph extends StatelessWidget {
  const _LoadedGraph({
    required this.points,
    required this.timeframe,
    required this.onTimeframe,
  });

  final List<RankProgressPoint> points;
  final RankTimeframe timeframe;
  final ValueChanged<RankTimeframe> onTimeframe;

  @override
  Widget build(BuildContext context) {
    final windowed = windowPoints(points, timeframe);
    final series = plottableSeries(windowed);
    final needed = windowed.isNotEmpty ? windowed.last.classesNeeded : 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingLarge,
      children: [
        RatingGraph(series: series, classesNeeded: needed),
        TimeframeSelector(selected: timeframe, onChanged: onTimeframe),
      ],
    );
  }
}

/// Keeps loading / error content in the same footprint the plotted graph uses.
class _GraphBox extends StatelessWidget {
  const _GraphBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: DesignConstants.screenHorizontalPadding,
      ),
      child: AspectRatio(aspectRatio: _kGraphAspect, child: child),
    );
  }
}

class _GraphError extends StatelessWidget {
  const _GraphError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _GraphBox(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: DesignConstants.spacingMedium,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
          ),
          TextButton(
            onPressed: onRetry,
            child: Text('Retry', style: DesignConstants.p),
          ),
        ],
      ),
    );
  }
}
