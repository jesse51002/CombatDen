import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/refresh/app_refresh.dart';
import 'package:mobile_app/core/refresh/refresh_signal.dart';
import 'package:mobile_app/features/home/bloc/home_bloc.dart';
import 'package:mobile_app/features/home/bloc/home_event.dart';
import 'package:mobile_app/features/home/bloc/home_state.dart';
import 'package:mobile_app/features/home/data/models/schedule_day.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_schedule_title.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/day_class_group.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/pinned_date_row_delegate.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/schedule_status.dart';
import 'package:mobile_app/features/home/presentation/widgets/home_error_view.dart';
import 'package:mobile_app/features/home/presentation/widgets/home_topbar.dart';
import 'package:mobile_app/features/home/presentation/widgets/upcoming_sessions/upcoming_sessions_card.dart';
import 'package:mobile_app/shared/widgets/refresh/app_refresh_view.dart';

const double _kDateRowHeight = 50;
// Trigger a window extension when the scroll gets this close to the bottom.
const double _kExtendThreshold = 500;

/// The single home body: topbar (streak/points), the "upcoming sessions" card
/// when the member has reservations, and the day-grouped schedule board under a
/// pinned date bar. Pull-to-refresh (the shared [AppRefresh] — identity /
/// capabilities / branding, theme, profile, and this board) + refetch-on-return;
/// the pinned date bar
/// highlights the current day (measured, so variable day heights stay in sync)
/// and jumps to a day on tap; scrolling to the bottom extends the window.
class HomeBody extends StatefulWidget {
  const HomeBody({super.key});

  @override
  State<HomeBody> createState() => _HomeBodyState();
}

class _HomeBodyState extends State<HomeBody> {
  final ScrollController _vertical = ScrollController();
  final ScrollController _dateController = ScrollController();
  final Map<int, GlobalKey> _dayKeys = {};
  int _currentDayIndex = 0;
  int? _extendRequestedForWindow;

  GlobalKey _dayKey(int offset) =>
      _dayKeys.putIfAbsent(offset, () => GlobalKey());

  @override
  void initState() {
    super.initState();
    _vertical.addListener(_onScroll);
  }

  @override
  void dispose() {
    _vertical.dispose();
    _dateController.dispose();
    super.dispose();
  }

  void _onScroll() {
    _updateCurrentDay();
    _maybeExtend();
  }

  // The day whose header sits just under the pinned date bar is the current
  // day. Measured per-day so variable-height days stay in sync.
  void _updateCurrentDay() {
    final offset = _vertical.hasClients ? _vertical.offset : 0.0;
    var current = 0;
    for (final entry in (_dayKeys.keys.toList()..sort())) {
      final ctx = _dayKeys[entry]?.currentContext;
      final box = ctx?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final reveal = RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset;
      if (reveal - _kDateRowHeight <= offset + 1) {
        current = entry;
      } else {
        break;
      }
    }
    if (current != _currentDayIndex) {
      setState(() => _currentDayIndex = current);
    }
  }

  void _maybeExtend() {
    if (!_vertical.hasClients) return;
    final pos = _vertical.position;
    if (pos.maxScrollExtent <= 0) return;
    if (pos.pixels < pos.maxScrollExtent - _kExtendThreshold) return;
    final bloc = context.read<HomeBloc>();
    final st = bloc.state;
    if (st.status != HomeStatus.loaded || st.isExtending || !st.canExtend) {
      return;
    }
    if (_extendRequestedForWindow == st.windowDays) return;
    _extendRequestedForWindow = st.windowDays;
    bloc.add(const HomeExtendRequested());
  }

  void _onDateTap(int index) {
    final ctx = _dayKeys[index]?.currentContext;
    final box = ctx?.findRenderObject() as RenderBox?;
    if (box == null || !_vertical.hasClients) return;
    final reveal = RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset;
    final target = (reveal - _kDateRowHeight)
        .clamp(0.0, _vertical.position.maxScrollExtent);
    _vertical.animateTo(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
    setState(() => _currentDayIndex = index);
  }

  /// The shared pull: identity + capabilities + branding, theme, the shared
  /// profile, and this screen's own board + reservations — all awaited.
  Future<void> _refresh() {
    final bloc = context.read<HomeBloc>();
    return AppRefresh.forScreen(
      context,
      screen: () => dispatchRefresh(bloc, HomeRefreshRequested.new),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomeBloc, HomeState>(
      builder: (context, state) {
        return AppRefreshView(
          onRefresh: _refresh,
          child: CustomScrollView(
            controller: _vertical,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: _slivers(state),
          ),
        );
      },
    );
  }

  List<Widget> _slivers(HomeState state) {
    if (state.status == HomeStatus.loaded) {
      return _loadedSlivers(state);
    }
    return [
      const SliverToBoxAdapter(child: HomeTopbar()),
      SliverFillRemaining(hasScrollBody: false, child: _statusBody(state)),
    ];
  }

  Widget _statusBody(HomeState state) {
    if (state.status == HomeStatus.error) {
      return HomeErrorView(
        message: state.errorMessage ?? "Couldn't load your schedule.",
        onRetry: () => context.read<HomeBloc>().add(const HomeLoadRequested()),
      );
    }
    return const ScheduleStatus(loading: true);
  }

  List<Widget> _loadedSlivers(HomeState state) {
    final days = groupOccurrencesByDay(state.occurrences, state.windowDays);
    return [
      SliverToBoxAdapter(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingBig,
          children: [
            const HomeTopbar(),
            if (state.upcoming.isNotEmpty) ...[
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: DesignConstants.screenHorizontalPadding,
                ),
                child: UpcomingSessionsCard(sessions: state.upcoming),
              ),
              const ClassScheduleTitle(),
            ],
          ],
        ),
      ),
      SliverPersistentHeader(
        pinned: true,
        delegate: PinnedDateRowDelegate(
          currentDayIndex: _currentDayIndex,
          dayCount: state.windowDays,
          scrollController: _dateController,
          height: _kDateRowHeight,
          onDateTap: _onDateTap,
        ),
      ),
      SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final day in days)
              KeyedSubtree(
                key: _dayKey(day.dayOffset),
                child: DayClassGroup(day: day, bookedKeys: state.bookedKeys),
              ),
            if (state.isExtending)
              Padding(
                padding: EdgeInsets.all(DesignConstants.spacingBig),
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    ];
  }
}
