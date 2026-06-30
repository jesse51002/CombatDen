import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/schedule/bloc/schedule_bloc.dart';
import 'package:crm/features/schedule/bloc/schedule_event.dart';
import 'package:crm/features/schedule/bloc/schedule_state.dart';
import 'package:crm/features/schedule/data/class_time_format.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';
import 'package:crm/features/schedule/data/models/gym_class_response.dart';
import 'package:crm/features/schedule/data/models/gym_class_view_models.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';
import 'package:crm/features/schedule/presentation/screens/class_form_screen.dart';
import 'package:crm/features/schedule/presentation/widgets/header/schedule_header_bar.dart';
import 'package:crm/features/schedule/presentation/widgets/list/schedule_class_list.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/app_shell.dart';
import 'package:crm/shared/widgets/section_card.dart';

final DateFormat _monthFormat = DateFormat('MMMM, yyyy');
final DateFormat _rangeFormat = DateFormat('MMM d, yyyy');
final DateFormat _dayColumnFormat = DateFormat('EEE, MMM d');

/// Gym Class Schedule screen — the read-only week board, wired live to the
/// FastAPI `classes` domain (`GET /api/v1/classes/instances`).
///
/// Provides the [ScheduleRepository] + [ScheduleBloc] and dispatches the
/// initial load for the current week. Scoped to the active gym UUID from the
/// [selectedGym] global. A null gym (never expected inside the authed
/// workspace) shows a friendly prompt instead of the board.
class ScheduleScreen extends StatelessWidget {
  const ScheduleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final gymId = selectedGym.gymId;
    if (gymId == null) {
      return const AppShell(
        activeRoute: AppRoutes.schedule,
        child: _ScheduleScroll(
          children: [
            _ScheduleTitle(),
            _ScheduleMessage('Select a gym to load its class schedule.'),
          ],
        ),
      );
    }
    final weekStart = _currentWeekStart();
    return RepositoryProvider<ScheduleRepository>(
      create: (_) => ScheduleRepository(apiClient: ApiClient()),
      child: BlocProvider<ScheduleBloc>(
        create: (ctx) => ScheduleBloc(
          repository: ctx.read<ScheduleRepository>(),
        )..add(ScheduleInitRequested(gymId: gymId, weekStart: weekStart)),
        child: AppShell(
          activeRoute: AppRoutes.schedule,
          child: _ScheduleBody(initialWeekStart: weekStart),
        ),
      ),
    );
  }
}

/// The Sunday (local midnight) that starts the week containing today.
/// TODO(class-system): uses the device date; the gym-local "today" is not yet
/// exposed to the CRM. Revisit once a gym timezone is available client-side.
DateTime _currentWeekStart() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return today.subtract(Duration(days: today.weekday % 7));
}

/// Open the create / edit class form, **sharing the board's [ScheduleBloc]**
/// (via `BlocProvider.value`) so a save reloads the board the user returns to.
/// Pushed directly with a `RouteSettings(name:)` — like the membership-plan
/// form — so the form sub-route keeps the schedule URL and inherits the bloc
/// (a bare named route could not). [context] must sit under the board's
/// `BlocProvider<ScheduleBloc>`.
///
/// Pass [occurrenceDate] (and [occurrenceCancelled]) when opening from a tapped
/// board card: the form then surfaces the single-occurrence actions ("Update
/// attendees" / "Cancel this class") for that date. Omit them for the header
/// "Add class" button (a brand-new class, no occurrence yet).
void _openClassForm(
  BuildContext context, {
  GymClassResponse? existing,
  DateTime? occurrenceDate,
  bool occurrenceCancelled = false,
}) {
  final bloc = context.read<ScheduleBloc>();
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: RouteSettings(
        name: existing == null
            ? AppRoutes.scheduleAddClass
            : AppRoutes.scheduleEditClass,
      ),
      builder: (_) => BlocProvider<ScheduleBloc>.value(
        value: bloc,
        child: ClassFormScreen(
          existing: existing,
          occurrenceDate: occurrenceDate,
          occurrenceCancelled: occurrenceCancelled,
        ),
      ),
    ),
  );
}

/// Tapping a board card opens the class **edit form** directly (no manage
/// popup), carrying the tapped occurrence's date + cancelled state so the form
/// can host that occurrence's actions. Resolves the card's class id to its real
/// [GymClassResponse] from the loaded catalog first; a miss (the class vanished
/// from a concurrent reload) is ignored.
void _onInstanceTap(
  BuildContext context,
  List<GymClassResponse> classes,
  ScheduleClassEntry entry,
) {
  for (final c in classes) {
    if (c.classId == entry.classId) {
      _openClassForm(
        context,
        existing: c,
        occurrenceDate: entry.classDate,
        occurrenceCancelled: entry.isCancelled,
      );
      return;
    }
  }
}

class _ScheduleBody extends StatefulWidget {
  final DateTime initialWeekStart;

  const _ScheduleBody({required this.initialWeekStart});

  @override
  State<_ScheduleBody> createState() => _ScheduleBodyState();
}

class _ScheduleBodyState extends State<_ScheduleBody> {
  late DateTime _weekStart;

  @override
  void initState() {
    super.initState();
    _weekStart = widget.initialWeekStart;
  }

  void _shiftWeek(int weeks) {
    setState(() => _weekStart = _weekStart.add(Duration(days: 7 * weeks)));
    context.read<ScheduleBloc>().add(ScheduleWeekChanged(_weekStart));
  }

  @override
  Widget build(BuildContext context) {
    final weekEnd = _weekStart.add(const Duration(days: 6));
    return _ScheduleScroll(
      children: [
        const _ScheduleTitle(),
        ScheduleHeaderBar(
          monthLabel: _monthFormat.format(_weekStart),
          rangeLabel:
              '${_rangeFormat.format(_weekStart)} - '
              '${_rangeFormat.format(weekEnd)}',
          onPrevious: () => _shiftWeek(-1),
          onNext: () => _shiftWeek(1),
          onAddClass: () => _openClassForm(context),
        ),
        _ScheduleBoard(weekStart: _weekStart),
      ],
    );
  }
}

/// Renders the bloc's [ScheduleLoaded] instances as the week board; shows a
/// spinner while loading and a message on error / empty.
class _ScheduleBoard extends StatelessWidget {
  final DateTime weekStart;

  const _ScheduleBoard({required this.weekStart});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ScheduleBloc, ScheduleState>(
      builder: (context, state) {
        switch (state) {
          case ScheduleError(:final message):
            return _ScheduleMessage(message);
          case ScheduleLoaded(:final instances, :final classes):
            final days = _buildDays(weekStart, instances);
            if (instances.isEmpty) {
              return const _ScheduleMessage(
                'No classes scheduled this week.',
              );
            }
            return ScheduleClassList(
              days: days,
              onClassTap: (entry) => _onInstanceTap(context, classes, entry),
            );
          case ScheduleInitial():
          case ScheduleLoading():
            return const _ScheduleMessage(null);
        }
      },
    );
  }
}

/// Group the week's [instances] into the seven day columns of the week that
/// starts at [weekStart] (Sunday). Dates + times are already gym-local — no
/// timezone math; render as given.
List<ScheduleDayGroup> _buildDays(
  DateTime weekStart,
  List<EffectiveClassInstance> instances,
) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final days = <ScheduleDayGroup>[];
  for (var d = 0; d < 7; d++) {
    final date = weekStart.add(Duration(days: d));
    final dayInstances = instances
        .where((i) => _isSameDay(i.classDate, date))
        .toList()
      ..sort((a, b) => a.resolvedClassTime.compareTo(b.resolvedClassTime));
    days.add(
      ScheduleDayGroup(
        dayLabel: _dayColumnFormat.format(date),
        isToday: _isSameDay(date, today),
        classes: dayInstances.map(_entryFromInstance).toList(),
      ),
    );
  }
  return days;
}

ScheduleClassEntry _entryFromInstance(EffectiveClassInstance i) =>
    ScheduleClassEntry(
      classId: i.classId,
      classDate: i.classDate,
      name: i.className,
      timeLabel:
          classTimeRangeLabel(i.resolvedClassTime, i.resolvedDurationMinutes),
      instructorName: i.resolvedInstructorName,
      imageUrl: i.imageUrl,
      pointsWorth: i.pointsWorth,
      attendeeCount: i.attendanceCount,
      occurrenceInPast: i.occurredAt.isBefore(DateTime.now()),
      isCancelled: i.isCancelled,
    );

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class _ScheduleScroll extends StatelessWidget {
  final List<Widget> children;

  const _ScheduleScroll({required this.children});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(DesignConstants.paddingBig),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingBig,
        children: children,
      ),
    );
  }
}

class _ScheduleTitle extends StatelessWidget {
  const _ScheduleTitle();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Gym Class Schedule',
      style: DesignConstants.h1.copyWith(color: DesignConstants.text2nd),
    );
  }
}

/// Loading (null message) / error / empty chrome for the board.
class _ScheduleMessage extends StatelessWidget {
  final String? message;

  const _ScheduleMessage(this.message);

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.all(DesignConstants.paddingBig),
      child: Center(
        child: message == null
            ? const AppSpinner()
            : Text(
                message!,
                style: DesignConstants.p.copyWith(
                  color: DesignConstants.text2nd,
                ),
                textAlign: TextAlign.center,
              ),
      ),
    );
  }
}
