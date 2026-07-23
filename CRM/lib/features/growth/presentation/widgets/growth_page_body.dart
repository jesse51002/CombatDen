import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/growth/bloc/growth_bloc.dart';
import 'package:crm/features/growth/bloc/growth_event.dart';
import 'package:crm/features/growth/bloc/growth_state.dart';
import 'package:crm/features/growth/presentation/tabs/attendance_tab.dart';
import 'package:crm/features/growth/presentation/tabs/members_tab.dart';
import 'package:crm/features/growth/presentation/tabs/overview_tab.dart';
import 'package:crm/features/growth/presentation/tabs/retention_tab.dart';
import 'package:crm/features/growth/presentation/tabs/revenue_tab.dart';
import 'package:crm/features/growth/presentation/tabs/trial_tab.dart';
import 'package:crm/features/growth/presentation/widgets/growth_range.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/empty_state.dart';

/// The Growth page's tab area: the six tab bodies, or the page-level
/// state that replaces them. The chrome above (tab bar, meta row) stays
/// mounted in every state.
class GrowthPageBody extends StatelessWidget {
  final GrowthState state;
  final int tabIndex;
  final GrowthRange range;
  final String? classId;
  final String? className;
  final bool compact;

  const GrowthPageBody({
    super.key,
    required this.state,
    required this.tabIndex,
    required this.range,
    required this.classId,
    required this.className,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    switch (state.status) {
      case GrowthStatus.initial:
      case GrowthStatus.loading:
        // One read serves all six tabs — there is no partial content to
        // skeleton around, so a single centered spinner it is.
        return const Center(
          child: AppSpinner(size: DesignConstants.spinnerSizeLarge),
        );
      case GrowthStatus.error:
        return Center(
          child: EmptyState(
            tone: EmptyStateTone.error,
            icon: Symbols.error_sharp,
            title: "Couldn't load your metrics",
            body: state.error ?? 'Something went wrong. Please try again.',
            action: AppOutlineButton(
              text: 'Try again',
              onPressed: () => context
                  .read<GrowthBloc>()
                  .add(const GrowthLoadRequested()),
            ),
          ),
        );
      case GrowthStatus.loaded:
        if (state.isNotComputedYet) {
          // Deliberately NO retry: the sweep runs on the backend's hourly
          // clock, so re-reading changes nothing. Nothing is broken here,
          // and it must not be dressed up as a failure.
          return const Center(
            child: EmptyState(
              icon: Symbols.query_stats_sharp,
              title: 'Your metrics are still being built',
              body: 'Growth recomputes every hour. The first run usually '
                  'lands within an hour of your gym going live.',
            ),
          );
        }
        // Order MUST match `_tabs` / `_categories` / `kGrowthTabRoutes` in
        // growth_screen.dart — the IndexedStack is indexed by tab position:
        // Overview · Revenue · Members · Retention · Trial · Attendance.
        return IndexedStack(
          index: tabIndex,
          children: [
            OverviewTab(state: state, range: range, compact: compact),
            RevenueTab(state: state, range: range, compact: compact),
            MembersTab(state: state, range: range, compact: compact),
            RetentionTab(state: state, range: range, compact: compact),
            TrialTab(state: state, range: range, compact: compact),
            AttendanceTab(
              state: state,
              range: range,
              classId: classId,
              className: className,
              compact: compact,
            ),
          ],
        );
    }
  }
}
