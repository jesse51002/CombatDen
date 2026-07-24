import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/core/navigation/url_sync.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/growth/bloc/growth_bloc.dart';
import 'package:crm/features/growth/bloc/growth_event.dart';
import 'package:crm/features/growth/bloc/growth_state.dart';
import 'package:crm/features/growth/data/models/growth_metric.dart';
import 'package:crm/features/growth/data/repositories/growth_repository.dart';
import 'package:crm/features/growth/presentation/widgets/growth_class_filter.dart';
import 'package:crm/features/growth/presentation/widgets/growth_meta_row.dart';
import 'package:crm/features/growth/presentation/widgets/growth_page_body.dart';
import 'package:crm/features/growth/presentation/widgets/growth_range.dart';
import 'package:crm/shared/widgets/app_shell.dart';
import 'package:crm/shared/widgets/view_switcher.dart';

/// The Growth tabs' routes, in tab order. `_onGenerateRoute` maps a
/// deep-linked path to its index through this list, and the screen writes
/// the matching path back on every tab switch — both directions read one
/// source, so they cannot drift.
const List<String> kGrowthTabRoutes = [
  AppRoutes.growth,
  AppRoutes.growthRevenue,
  AppRoutes.growthMembers,
  AppRoutes.growthRetention,
  AppRoutes.growthTrial,
  AppRoutes.growthAttendance,
];

/// Growth (analytics) screen — six tabs over ONE cached backend read.
///
/// The backend recomputes each gym's metrics on its own hourly clock; this
/// page only ever reads. Switching tabs, narrowing the range and picking a
/// class are all client-side reshapes of the page already in memory —
/// none of them refetches.
class GrowthScreen extends StatelessWidget {
  /// Tab to open on (0 Overview … 5 Attendance).
  final int initialTab;

  const GrowthScreen({super.key, this.initialTab = 0});

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider<GrowthRepository>(
      create: (_) => GrowthRepository(apiClient: ApiClient()),
      child: BlocProvider<GrowthBloc>(
        create: (ctx) => GrowthBloc(
          repository: ctx.read<GrowthRepository>(),
        )..add(const GrowthLoadRequested()),
        child: AppShell(
          activeRoute: AppRoutes.growth,
          child: GrowthView(initialTab: initialTab),
        ),
      ),
    );
  }
}

/// The Growth page below the app shell: tab bar, meta row, tab bodies.
///
/// Split out from [GrowthScreen] so it can be driven by any supplied
/// [GrowthBloc]; the screen wires the real repository above it.
class GrowthView extends StatefulWidget {
  final int initialTab;

  const GrowthView({super.key, this.initialTab = 0});

  @override
  State<GrowthView> createState() => _GrowthViewState();
}

class _GrowthViewState extends State<GrowthView> {
  static const _tabs = [
    'Overview',
    'Revenue',
    'Members',
    'Retention',
    'Trial',
    'Attendance',
  ];

  static const _categories = [
    GrowthCategory.overview,
    GrowthCategory.revenue,
    GrowthCategory.members,
    GrowthCategory.retention,
    GrowthCategory.trial,
    GrowthCategory.attendance,
  ];

  /// The Attendance tab's index — the one tab carrying class chips.
  static const _attendanceTab = 5;

  late int _tabIndex;
  GrowthRange _range = GrowthRange.all;
  String? _classId;

  @override
  void initState() {
    super.initState();
    _tabIndex = widget.initialTab.clamp(0, _tabs.length - 1);
  }

  // Tab switching is a local setState (the IndexedStack keeps each tab's
  // scroll offset alive), so reflect the open tab into the URL ourselves.
  void _onTabSelected(int i) {
    setState(() => _tabIndex = i);
    syncBrowserUrl(kGrowthTabRoutes[i]);
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <
        DesignConstants.navMobileBreakpoint;

    return BlocBuilder<GrowthBloc, GrowthState>(
      builder: (context, state) {
        final classOptions =
            classOptionsFor(state.metricsIn(GrowthCategory.attendance));
        // A class that vanished from the data (a gym switch, a recompute)
        // must not leave a dead selection filtering every section.
        GrowthClassOption? selected;
        for (final o in classOptions) {
          if (o.classId == _classId) selected = o;
        }

        final hasPage = state.status == GrowthStatus.loaded &&
            !state.isNotComputedYet &&
            state.metrics.isNotEmpty;
        final showRange = hasPage &&
            anyMetricHasSeries(state.metricsIn(_categories[_tabIndex]));
        final showClasses = hasPage &&
            _tabIndex == _attendanceTab &&
            classOptions.isNotEmpty;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingBig,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                top: DesignConstants.paddingBig,
                left: DesignConstants.screenHorizontalPadding,
                right: DesignConstants.screenHorizontalPadding,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: DesignConstants.spacingBig,
                children: [
                  ViewSwitcher(
                    labels: _tabs,
                    selectedIndex: _tabIndex,
                    onSelected: _onTabSelected,
                    // Six tabs at the default 16pt overflow below ~790px.
                    textStyle: compact ? DesignConstants.h3 : null,
                  ),
                  // Omitted entirely while there is nothing to stamp or
                  // filter, so the first load has no empty band under the
                  // tabs.
                  if (showRange || showClasses || state.computedAt != null)
                    GrowthMetaRow(
                      computedAt: state.computedAt,
                      range: _range,
                      onRange:
                          showRange ? (r) => setState(() => _range = r) : null,
                      classOptions: showClasses ? classOptions : const [],
                      selectedClassId: selected?.classId,
                      onClass: (id) => setState(() => _classId = id),
                    ),
                ],
              ),
            ),
            Expanded(
              child: GrowthPageBody(
                state: state,
                tabIndex: _tabIndex,
                range: _range,
                classId: selected?.classId,
                className: selected?.className,
                compact: compact,
              ),
            ),
          ],
        );
      },
    );
  }
}
