import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import 'package:crm/core/auth/role_policy.dart';
import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/schedule/bloc/schedule_bloc.dart';
import 'package:crm/features/schedule/bloc/schedule_event.dart';
import 'package:crm/features/schedule/bloc/schedule_state.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';
import 'package:crm/features/schedule/data/models/gym_class_response.dart';
import 'package:crm/features/schedule/data/models/gym_class_view_models.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';
import 'package:crm/features/schedule/data/schedule_week.dart';
import 'package:crm/features/schedule/presentation/dialogs/class_occurrence_chooser_dialog.dart';
import 'package:crm/features/schedule/presentation/screens/class_form_screen.dart';
import 'package:crm/features/schedule/presentation/screens/class_occurrence_screen.dart';
import 'package:crm/features/schedule/presentation/widgets/header/schedule_header_bar.dart';
import 'package:crm/features/schedule/presentation/widgets/list/schedule_class_list.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/app_shell.dart';
import 'package:crm/shared/widgets/section_card.dart';

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
    final weekStart = currentWeekStart();
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

/// Open the **class definition** form (create, or edit a class's recurring
/// rules), **sharing the board's [ScheduleBloc]** (via `BlocProvider.value`) so
/// a save reloads the board the user returns to. Pushed directly with a
/// `RouteSettings(name:)` — like the membership-plan form — so the form
/// sub-route keeps the schedule URL and inherits the bloc (a bare named route
/// could not). [context] must sit under the board's `BlocProvider<ScheduleBloc>`.
void _openClassForm(BuildContext context, {GymClassResponse? existing}) {
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
        child: ClassFormScreen(existing: existing),
      ),
    ),
  );
}

/// Open the **occurrence-edit** screen for one tapped board card (this day's
/// instructor / time / capacity overrides, attendance, cancel-this-day).
/// Sharing the board's [ScheduleBloc] like [_openClassForm].
void _openOccurrenceScreen(BuildContext context, ScheduleClassEntry entry) {
  final bloc = context.read<ScheduleBloc>();
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: AppRoutes.scheduleOccurrence),
      builder: (_) => BlocProvider<ScheduleBloc>.value(
        value: bloc,
        child: ClassOccurrenceScreen(entry: entry),
      ),
    ),
  );
}

/// Where a tap on a board card leads. The rule itself lives in
/// [scheduleTapTarget]; this is just the vocabulary.
enum ScheduleTapTarget {
  /// The occurrence screen — that one day's roster, attendance and sign-ups.
  occurrence,

  /// The class-definition editor — the recurring rules for every future day.
  classEditor,

  /// The "This occurrence / All future occurrences" chooser dialog.
  chooser,
}

/// The board's whole tap rule, as a pure function of the caller's
/// schedule-edit capability and whether the tapped class is paused. Extracted
/// so the rule is testable on its own — `_onInstanceTap` only dispatches it.
///
/// See [_onInstanceTap] for why each arm is what it is; the load-bearing one is
/// that a non-editor reaches the occurrence screen for a PAUSED class too.
ScheduleTapTarget scheduleTapTarget({
  required bool canEditSchedule,
  required bool isActive,
}) {
  if (!canEditSchedule) return ScheduleTapTarget.occurrence;
  return isActive ? ScheduleTapTarget.chooser : ScheduleTapTarget.classEditor;
}

/// Tapping a board card.
///
/// **Front desk + trainer** (who can't edit the recurring definition) always go
/// straight to the occurrence screen — the only destination they have access to
/// — **whether the class is active or PAUSED**. A paused class still carries the
/// attendance and sign-up history of every day it ran, and the roster is the
/// only place staff can read it, so the tap must lead there. Its check-in /
/// reserve / cancel actions are the ones the backend refuses on a paused class
/// (`class_inactive`), which surfaces as an error on the attempt; that is the
/// accepted cost of keeping the history reachable, and it beats a card that
/// silently does nothing at all when tapped.
///
/// For **owner/admin** (`canEditSchedule`): a PAUSED card (this board is the
/// only surface that offers them) opens the class editor directly, because
/// un-pausing is the reason those cards render for an editor and there is
/// nothing to choose between. An ACTIVE card opens the small **chooser dialog**
/// first: "This occurrence" (the occurrence-edit screen) or "All future
/// occurrences" (the class definition editor).
///
/// Both editor paths resolve the card's class id to its real
/// [GymClassResponse] from the loaded catalog; a miss (the class vanished from
/// a concurrent reload) is ignored.
void _onInstanceTap(
  BuildContext context,
  List<GymClassResponse> classes,
  ScheduleClassEntry entry,
) {
  final target = scheduleTapTarget(
    canEditSchedule: selectedGym.role?.canEditSchedule ?? false,
    isActive: entry.isActive,
  );
  if (target == ScheduleTapTarget.occurrence) {
    _openOccurrenceScreen(context, entry);
    return;
  }
  // Both remaining (editor) targets need the real class row, so resolve it
  // first and ignore a miss — never open a chooser whose editor option no-ops.
  final owning = _classById(classes, entry.classId);
  if (owning == null) return;
  if (target == ScheduleTapTarget.classEditor) {
    _openClassForm(context, existing: owning);
    return;
  }
  ClassOccurrenceChooserDialog.show(
    context: context,
    className: entry.name,
    occurrenceDate: entry.classDate,
    onThisOccurrence: () => _openOccurrenceScreen(context, entry),
    onAllFuture: () => _openClassForm(context, existing: owning),
  );
}

/// The loaded catalog row for [classId], or null when it isn't loaded (the
/// class vanished from a concurrent reload).
GymClassResponse? _classById(
  List<GymClassResponse> classes,
  String classId,
) {
  for (final c in classes) {
    if (c.classId == classId) return c;
  }
  return null;
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
          rangeLabel:
              '${_rangeFormat.format(_weekStart)} - '
              '${_rangeFormat.format(weekEnd)}',
          onPrevious: () => _shiftWeek(-1),
          onNext: () => _shiftWeek(1),
          onAddClass: () => _openClassForm(context),
          showAddClass: selectedGym.role?.canEditSchedule ?? false,
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
        classes:
            dayInstances.map(ScheduleClassEntry.fromInstance).toList(),
      ),
    );
  }
  return days;
}

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
