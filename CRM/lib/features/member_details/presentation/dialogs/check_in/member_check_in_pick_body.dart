import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/error_message.dart';

/// Check-in opens this many hours before a class starts (mirrors the backend
/// `checkin_opens_hours_before_start`), matching
/// `ClassOccurrenceScreen._kCheckInOpensHours`.
const int _kCheckInOpensHours = 2;

/// How far back the past-classes picker reaches.
const int _kLookbackDays = 30;

/// How far forward the Reserve picker reaches.
const int _kHorizonDays = 14;

/// Builds the pick phase's content once the load settles, given the three
/// CLIENT-SIDE splits of the loaded window (see [MemberCheckInPickBody]).
typedef CheckInPickBuilder = Widget Function(
  BuildContext context,
  List<EffectiveClassInstance> checkIn,
  List<EffectiveClassInstance> past,
  List<EffectiveClassInstance> reserve,
);

/// The check-in/reserve dialog's data loader: loads every effective
/// occurrence in one `[today - 30d, today + 14d]` window via
/// `ScheduleRepository.listEffectiveInstances`, drops cancelled days, then
/// splits it CLIENT-SIDE by each occurrence's UTC start instant
/// (`occurredAt`, see [_startOf]) / end (`+ resolvedDurationMinutes`)
/// against `DateTime.now()`:
///
/// - **Check in**: in session OR starting within the next 2h
///   (`_kCheckInOpensHours`, mirroring the backend
///   `checkin_opens_hours_before_start`) — soonest first.
/// - **Past**: already ended — most recent first (feeds the "Check into a
///   past class" identity picker, then that class's occurrences).
/// - **Reserve**: any occurrence that hasn't started yet — soonest first
///   (feeds the Reserve identity picker, then that class's occurrences).
///   This INTENTIONALLY overlaps Check-in: a class starting within the next
///   2h appears in BOTH — a class already in session appears only in
///   Check-in.
///
/// Pure data + loading/error chrome; the pick-phase NAVIGATION (which view,
/// which step, which class/occurrence is picked) lives in the dialog's own
/// state and is handed the three lists via [builder] so it never re-fetches
/// on a step or view change.
class MemberCheckInPickBody extends StatefulWidget {
  final String gymId;
  final CheckInPickBuilder builder;

  const MemberCheckInPickBody({
    super.key,
    required this.gymId,
    required this.builder,
  });

  @override
  State<MemberCheckInPickBody> createState() => _MemberCheckInPickBodyState();
}

class _MemberCheckInPickBodyState extends State<MemberCheckInPickBody> {
  List<EffectiveClassInstance> _checkIn = [];
  List<EffectiveClassInstance> _past = [];
  List<EffectiveClassInstance> _reserve = [];
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// The occurrence's effective start INSTANT — the backend-computed UTC
  /// `occurredAt`, the same instant the check-in gate enforces. Never
  /// rebuilt from `classDate` + `resolvedClassTime` in the browser's
  /// timezone: those are GYM-local wall-clock fields (display only), so a
  /// staff member whose browser tz differs from the gym's would bucket an
  /// in-session class as not-yet-started (or offer a check-in the backend
  /// rejects). Dart compares instants by epoch, so `occurredAt` (UTC) vs
  /// `DateTime.now()` (local) is exact.
  DateTime _startOf(EffectiveClassInstance i) => i.occurredAt;

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
    return widget.builder(context, _checkIn, _past, _reserve);
  }
}
