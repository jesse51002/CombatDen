import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/check_in/check_in_reserve_selection.dart';
import 'package:crm/features/member_details/presentation/dialogs/check_in/check_in_section.dart';
import 'package:crm/features/schedule/data/class_time_format.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/error_message.dart';

/// Check-in opens this many hours before a class starts (mirrors the backend
/// `checkin_opens_hours_before_start`), matching
/// `ClassOccurrenceScreen._kCheckInOpensHours`.
const int _kCheckInOpensHours = 2;

/// How far back "Show past classes" reaches.
const int _kLookbackDays = 30;

/// How far forward the Reserve section reaches.
const int _kHorizonDays = 14;

/// The check-in/reserve dialog's selection body. Loads every effective
/// occurrence in one `[today - 30d, today + 14d]` window, drops cancelled
/// days, then splits it CLIENT-SIDE by each occurrence's computed start
/// (`classDate` + `resolvedClassTime`) / end (`+ resolvedDurationMinutes`)
/// against `DateTime.now()`:
///
/// - **Check in** (emphasized, always shown): in session OR starting within
///   the next 2h (`start <= now + 2h` and not yet ended) — soonest first.
/// - **Past classes** (behind a "Show past classes" toggle, hidden by
///   default): already ended (`end <= now`) — most recent first.
/// - **Reserve**: any occurrence that hasn't started yet (`start > now`,
///   i.e. not currently in session) — soonest first. This INTENTIONALLY
///   overlaps Check-in: a class starting within the next 2h appears in BOTH
///   sections (pick the Check-in tile to record attendance now, or the
///   Reserve tile to hold a spot); a class already in session appears only
///   under Check-in.
///
/// Picking a tile emits a [CheckInReserveSelection] carrying which action it
/// drives, since the same occurrence can appear under both actions.
class MemberCheckInPickBody extends StatefulWidget {
  final String gymId;
  final String? selectedKey;
  final ValueChanged<CheckInReserveSelection> onSelect;

  const MemberCheckInPickBody({
    super.key,
    required this.gymId,
    required this.onSelect,
    this.selectedKey,
  });

  @override
  State<MemberCheckInPickBody> createState() =>
      _MemberCheckInPickBodyState();
}

class _MemberCheckInPickBodyState extends State<MemberCheckInPickBody> {
  List<EffectiveClassInstance> _checkIn = [];
  List<EffectiveClassInstance> _past = [];
  List<EffectiveClassInstance> _reserve = [];
  bool _showPast = false;
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// The occurrence's effective local start instant (`classDate` +
  /// `resolvedClassTime`) — arbitrary-timezone-free, matching how the rest
  /// of the schedule feature renders these fields (as given, no tz math).
  DateTime _startOf(EffectiveClassInstance i) {
    final time = parseHmsTime(i.resolvedClassTime) ??
        const TimeOfDay(hour: 0, minute: 0);
    return DateTime(
      i.classDate.year,
      i.classDate.month,
      i.classDate.day,
      time.hour,
      time.minute,
    );
  }

  Future<void> _load() async {
    final repo = context.read<ScheduleRepository>();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    try {
      final all = await repo.listEffectiveInstances(
        widget.gymId,
        today.subtract(const Duration(days: _kLookbackDays)),
        today.add(const Duration(days: _kHorizonDays)),
      );
      if (!mounted) return;

      final checkInWindowEnd =
          now.add(const Duration(hours: _kCheckInOpensHours));
      final checkIn = <EffectiveClassInstance>[];
      final past = <EffectiveClassInstance>[];
      final reserve = <EffectiveClassInstance>[];
      for (final i in all) {
        if (i.isCancelled) continue;
        final start = _startOf(i);
        final end = start.add(Duration(minutes: i.resolvedDurationMinutes));
        if (!end.isAfter(now)) {
          // Already ended.
          past.add(i);
        } else if (!start.isAfter(checkInWindowEnd)) {
          // In session, or starts within the check-in window.
          checkIn.add(i);
        }
        // Independent of the branches above: any occurrence that hasn't
        // started yet is reservable — this is what makes a class starting
        // within the next 2h show up under BOTH Check-in and Reserve.
        if (start.isAfter(now)) reserve.add(i);
      }
      checkIn.sort((a, b) => _startOf(a).compareTo(_startOf(b)));
      past.sort((a, b) => _startOf(b).compareTo(_startOf(a)));
      reserve.sort((a, b) => _startOf(a).compareTo(_startOf(b)));

      setState(() {
        _checkIn = checkIn;
        _past = past;
        _reserve = reserve;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'We couldn’t load the class schedule. Please retry.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: DesignConstants.dialogProcessingHeight,
        child: Center(child: AppSpinner()),
      );
    }
    if (_loadError != null) return ErrorMessage(message: _loadError!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        CheckInSection(
          title: 'Check in',
          action: CheckInReserveAction.checkIn,
          instances: _checkIn,
          selectedKey: widget.selectedKey,
          onSelect: widget.onSelect,
          emptyLabel: 'No classes open for check-in right now.',
        ),
        if (_past.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: AppOutlineButton(
              text: _showPast ? 'Hide past classes' : 'Show past classes',
              borderRadius: DesignConstants.radiusSmall,
              onPressed: () => setState(() => _showPast = !_showPast),
            ),
          ),
        if (_showPast && _past.isNotEmpty)
          CheckInSection(
            title: 'Past classes',
            action: CheckInReserveAction.checkIn,
            instances: _past,
            selectedKey: widget.selectedKey,
            onSelect: widget.onSelect,
          ),
        if (_reserve.isNotEmpty)
          CheckInSection(
            title: 'Reserve',
            action: CheckInReserveAction.reserve,
            instances: _reserve,
            selectedKey: widget.selectedKey,
            onSelect: widget.onSelect,
          ),
      ],
    );
  }
}
