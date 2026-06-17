import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/tasks/bloc/tasks_bloc.dart';
import 'package:crm/features/tasks/bloc/tasks_state.dart';
import 'package:crm/features/tasks/data/models/task_enums.dart';

/// Shows a progress bar + status line while a batch reprice
/// task is in flight ([TaskPolling]) and a terminal banner
/// when it finishes ([TaskPollingDone]).
///
/// Renders nothing when the [TasksBloc] is in any other state.
class RepriceTaskProgress extends StatelessWidget {
  const RepriceTaskProgress({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TasksBloc, TasksState>(
      buildWhen: (prev, curr) =>
          curr is TaskPolling ||
          curr is TaskPollingDone ||
          (prev is TaskPolling && curr is! TaskPolling) ||
          (prev is TaskPollingDone && curr is! TaskPollingDone),
      builder: (context, state) {
        final banner = switch (state) {
          TaskPolling() => _PollingView(state: state),
          TaskPollingDone() => _DoneView(state: state),
          _ => null,
        };
        // Zero-footprint (no padding, no gap) when idle so the table
        // sits flush; the screen-edge gutter is owned here when shown.
        if (banner == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(
            left: DesignConstants.screenHorizontalPadding,
            right: DesignConstants.screenHorizontalPadding,
            bottom: DesignConstants.spacingMedium,
          ),
          child: banner,
        );
      },
    );
  }
}

class _PollingView extends StatelessWidget {
  final TaskPolling state;

  const _PollingView({required this.state});

  @override
  Widget build(BuildContext context) {
    final progress = state.progress;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DesignConstants.spacingMedium),
      decoration: BoxDecoration(
        color: DesignConstants.accentSoft,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        border: Border.all(color: DesignConstants.primaryColor25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingSmall,
        children: [
          Row(
            spacing: DesignConstants.spacingSmall,
            children: [
              Icon(
                Icons.sync,
                size: DesignConstants.iconSizeSmall,
                color: DesignConstants.primaryColor,
              ),
              Expanded(
                child: Text(
                  'Upgrading ${state.completed} of '
                  '${state.total} member(s)…',
                  style: DesignConstants.pSmall.copyWith(
                    color: DesignConstants.primaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          LinearProgressIndicator(
            value: progress,
            backgroundColor:
                DesignConstants.primaryColor.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation<Color>(
              DesignConstants.primaryColor,
            ),
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
          ),
        ],
      ),
    );
  }
}

class _DoneView extends StatelessWidget {
  final TaskPollingDone state;

  const _DoneView({required this.state});

  @override
  Widget build(BuildContext context) {
    final failed = state.task.status == TaskStatus.failed;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DesignConstants.spacingMedium),
      decoration: BoxDecoration(
        color: failed
            ? DesignConstants.badRed.withValues(alpha: 0.08)
            : DesignConstants.goodGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        border: Border.all(
          color: failed ? DesignConstants.badRed : DesignConstants.goodGreen,
        ),
      ),
      child: Row(
        spacing: DesignConstants.spacingSmall,
        children: [
          Icon(
            failed ? Symbols.error_sharp : Symbols.check_circle_sharp,
            size: DesignConstants.iconSizeSmall,
            weight: DesignConstants.iconWeight,
            color: failed
                ? DesignConstants.badRed
                : DesignConstants.goodGreen,
          ),
          Expanded(
            child: Text(
              failed
                  ? 'Upgrade failed — ${state.task.completedCount} of '
                      '${state.task.totalCount} member(s) upgraded before '
                      'the error.'
                  : 'Upgrade complete — ${state.task.completedCount} '
                      'member(s) upgraded.',
              style: DesignConstants.pSmall.copyWith(
                color: failed
                    ? DesignConstants.badRed
                    : DesignConstants.goodGreen,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
