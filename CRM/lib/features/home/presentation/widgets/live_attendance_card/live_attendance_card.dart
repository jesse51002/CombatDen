import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/home/bloc/live_attendance_bloc.dart';
import 'package:crm/features/home/bloc/live_attendance_event.dart';
import 'package:crm/features/home/bloc/live_attendance_state.dart';
import 'package:crm/features/home/presentation/widgets/live_attendance_card/live_attendance_footer.dart';
import 'package:crm/features/home/presentation/widgets/live_attendance_card/live_attendance_header.dart';
import 'package:crm/features/home/presentation/widgets/live_attendance_card/live_attendance_roster.dart';
import 'package:crm/features/home/presentation/widgets/live_attendance_card/live_attendance_states.dart';
import 'package:crm/features/schedule/bloc/schedule_bloc.dart';
import 'package:crm/features/schedule/bloc/schedule_event.dart';
import 'package:crm/features/schedule/bloc/schedule_state.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';
import 'package:crm/features/schedule/data/schedule_week.dart';

/// Poll cadence — front-desk check-ins appear without a reload.
const Duration _kRefreshInterval = Duration(seconds: 60);

/// Top section of the dashboard's left column: the LIVE class roster — the
/// in-session occurrence(s)' combined signed-up ∪ attended members, each
/// flagged Checked In / Not Here, falling forward to the next class's
/// reservations when nothing is running. Self-contained like the Overdue /
/// Upcoming cards: owns a [ScheduleRepository] + [LiveAttendanceBloc]
/// (data + 60s poll) plus a loaded [ScheduleBloc] backing the footer's real
/// batch check-in / occurrence-screen actions. It fills its (equal-flex)
/// half of the column — the roster scrolls between a fixed header and a
/// **pinned** footer so the action buttons stay visible.
class LiveAttendanceCard extends StatelessWidget {
  const LiveAttendanceCard({super.key});

  @override
  Widget build(BuildContext context) {
    final gymId = selectedGym.gymId;
    if (gymId == null) {
      return const _Frame(
        header: LiveAttendanceHeader(),
        body: LiveAttendanceMessage('Select a gym to load its attendance.'),
      );
    }
    return RepositoryProvider<ScheduleRepository>(
      create: (_) => ScheduleRepository(apiClient: ApiClient()),
      child: MultiBlocProvider(
        providers: [
          BlocProvider<LiveAttendanceBloc>(
            create: (ctx) => LiveAttendanceBloc(
              repository: ctx.read<ScheduleRepository>(),
            )..add(LiveAttendanceLoadRequested(gymId)),
          ),
          // The footer's batch check-in dialog and occurrence screen both
          // dispatch schedule mutations, so the card hosts its own LOADED
          // ScheduleBloc — the same wiring they get from the board.
          // loadBoard: false — the card never renders the week board, so
          // only the class catalog is fetched on the dashboard hot path.
          BlocProvider<ScheduleBloc>(
            create: (ctx) => ScheduleBloc(
              repository: ctx.read<ScheduleRepository>(),
            )..add(
                ScheduleInitRequested(
                  gymId: gymId,
                  weekStart: currentWeekStart(),
                  loadBoard: false,
                ),
              ),
          ),
        ],
        child: _LiveAttendanceBody(gymId: gymId),
      ),
    );
  }
}

/// Hosts the poll timer and renders the bloc's state.
class _LiveAttendanceBody extends StatefulWidget {
  final String gymId;

  const _LiveAttendanceBody({required this.gymId});

  @override
  State<_LiveAttendanceBody> createState() => _LiveAttendanceBodyState();
}

class _LiveAttendanceBodyState extends State<_LiveAttendanceBody> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_kRefreshInterval, (_) => _onTick());
  }

  void _onTick() {
    context
        .read<LiveAttendanceBloc>()
        .add(const LiveAttendanceRefreshRequested());
    // Self-heal the footer's ScheduleBloc too: it has no poll of its own,
    // so a failed init would otherwise stick as ScheduleError and silently
    // disable the footer buttons under a perfectly healthy roster.
    final schedule = context.read<ScheduleBloc>();
    if (schedule.state is ScheduleError) {
      schedule.add(ScheduleInitRequested(
        gymId: widget.gymId,
        weekStart: currentWeekStart(),
        loadBoard: false,
      ));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LiveAttendanceBloc, LiveAttendanceState>(
      builder: (context, state) {
        switch (state) {
          case LiveAttendanceError(:final gymId):
            return _Frame(
              header: const LiveAttendanceHeader(),
              body: LiveAttendanceErrorBody(gymId: gymId),
            );
          case LiveAttendanceLoaded():
            return _Frame(
              header: LiveAttendanceHeader(
                subtitle: LiveAttendanceHeader.summaryFor(state),
              ),
              body: SingleChildScrollView(
                child: LiveAttendanceRoster(
                  sections: state.sections,
                  isNextPreview: state.isNextPreview,
                ),
              ),
              footer: LiveAttendanceFooter(
                target:
                    state.sections.isEmpty ? null : state.sections.first,
              ),
            );
          case LiveAttendanceInitial():
          case LiveAttendanceLoading():
            return const _Frame(
              header: LiveAttendanceHeader(),
              body: LiveAttendanceMessage(null),
            );
        }
      },
    );
  }
}

/// Fixed header, scrolling body, optional pinned footer.
class _Frame extends StatelessWidget {
  final Widget header;
  final Widget body;
  final Widget? footer;

  const _Frame({required this.header, required this.body, this.footer});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingBig,
      children: [
        header,
        Expanded(child: body),
        ?footer,
      ],
    );
  }
}
