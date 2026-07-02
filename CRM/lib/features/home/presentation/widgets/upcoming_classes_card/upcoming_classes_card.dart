import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/home/bloc/upcoming_classes_bloc.dart';
import 'package:crm/features/home/bloc/upcoming_classes_event.dart';
import 'package:crm/features/home/bloc/upcoming_classes_state.dart';
import 'package:crm/features/home/data/upcoming_classes.dart';
import 'package:crm/features/home/data/upcoming_classes_generator.dart';
import 'package:crm/features/home/presentation/widgets/upcoming_classes_card/_class_day_group.dart';
import 'package:crm/features/home/presentation/widgets/upcoming_classes_card/_upcoming_states.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';

/// Right-hand dashboard panel: a day-grouped list of the gym's upcoming
/// classes, read **live** from the real schedule feed (the same
/// `GET /api/v1/classes/instances` occurrences the Schedule board uses) for the
/// next two weeks. Self-contained — it owns a [ScheduleRepository] +
/// [UpcomingClassesBloc] so the rest of the dashboard stays stateless.
///
/// The card is **capped at the viewport height** and renders top-down: once it
/// fills the cap it stops, and anything beyond is clipped ("cut off") rather
/// than growing the dashboard unbounded. Tapping any class opens the full
/// Schedule screen, so the clipped rows stay reachable.
class UpcomingClassesCard extends StatelessWidget {
  const UpcomingClassesCard({super.key});

  @override
  Widget build(BuildContext context) {
    final gymId = selectedGym.gymId;
    if (gymId == null) {
      return const _UpcomingShell(
        child: UpcomingClassesMessage('Select a gym to load its classes.'),
      );
    }
    return RepositoryProvider<ScheduleRepository>(
      create: (_) => ScheduleRepository(apiClient: ApiClient()),
      child: BlocProvider<UpcomingClassesBloc>(
        create: (ctx) => UpcomingClassesBloc(
          repository: ctx.read<ScheduleRepository>(),
        )..add(UpcomingClassesLoadRequested(gymId)),
        child: const _UpcomingShell(child: _UpcomingBody()),
      ),
    );
  }
}

/// Title + viewport-capped body chrome shared by every state.
class _UpcomingShell extends StatelessWidget {
  final Widget child;
  const _UpcomingShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingBig,
        children: [
          Text('Upcoming Classes', style: DesignConstants.h1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _UpcomingBody extends StatelessWidget {
  const _UpcomingBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UpcomingClassesBloc, UpcomingClassesState>(
      builder: (context, state) {
        switch (state) {
          case UpcomingClassesError(:final gymId):
            return UpcomingClassesErrorBody(gymId: gymId);
          case UpcomingClassesLoaded(:final instances):
            final groups = upcomingClassesFromInstances(instances);
            if (groups.isEmpty) {
              return const UpcomingClassesMessage(
                'No upcoming classes scheduled.',
              );
            }
            // Lay the day list out at its natural height but clip it to the
            // card's (viewport-capped) bounds, top-aligned, so it cuts off
            // instead of extending. The clipped rows live on the Schedule
            // screen.
            return ClipRect(
              child: OverflowBox(
                alignment: Alignment.topCenter,
                minHeight: 0,
                maxHeight: double.infinity,
                child: _DayGroups(dayGroups: groups),
              ),
            );
          case UpcomingClassesInitial():
          case UpcomingClassesLoading():
            return const UpcomingClassesMessage(null);
        }
      },
    );
  }
}

class _DayGroups extends StatelessWidget {
  final List<ScheduledClassDayGroup> dayGroups;
  const _DayGroups({required this.dayGroups});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        for (final g in dayGroups) ClassDayGroup(group: g),
      ],
    );
  }
}

