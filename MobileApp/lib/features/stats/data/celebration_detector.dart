import 'dart:developer';

import 'package:flutter/widgets.dart';

import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/home/data/models/class_history.dart';
import 'package:mobile_app/features/home/data/repositories/member_class_history_repository.dart';
import 'package:mobile_app/features/stats/data/celebration_data.dart';
import 'package:mobile_app/features/stats/data/celebration_rules.dart';
import 'package:mobile_app/features/stats/data/celebration_watermark.dart';

/// Watches the app-open path for a fresh staff check-in and, when the newest
/// attended class is one the member hasn't seen celebrated yet, pushes the
/// post-class celebration flow ONCE.
///
/// Decoupled + failure-safe by design: a class-history fetch failure logs and
/// skips — it never crashes or blocks the home screen. The watermark advances
/// BEFORE the flow is shown, so the celebration fires exactly once and never
/// replays, even if the app is killed mid-flow.
class CelebrationDetector {
  CelebrationDetector({
    MemberClassHistoryRepository? historyRepository,
    CelebrationWatermark watermark = const CelebrationWatermark(),
  })  : _history = historyRepository ??
            MemberClassHistoryRepository(apiClient: ApiClient()),
        _watermark = watermark;

  final MemberClassHistoryRepository _history;
  final CelebrationWatermark _watermark;

  /// Guards against overlapping fetches (two foregrounds in quick succession).
  bool _inFlight = false;

  /// Fetch the class-history head, apply the watermark rule, and — on a fire —
  /// push the celebration onto [navigator]. Safe to call on every app open /
  /// foreground; a no-op when no member is selected or a fetch fails.
  Future<void> maybeFire(NavigatorState? navigator) async {
    if (_inFlight) return;
    final memberId = selectedMember.memberId;
    final gymId = selectedMember.gymId;
    if (memberId == null || gymId == null) return;
    _inFlight = true;
    try {
      final history =
          await _history.getHistory(gymId: gymId, memberId: memberId);
      final newest = _newestAttended(history.history);
      if (newest == null) return;
      final occurredAt = DateTime.tryParse(newest.occurredAt!);
      if (occurredAt == null) return;

      final decision = decideCelebration(
        lastSeen: await _watermark.lastSeen(memberId),
        newestAttended: occurredAt,
      );
      switch (decision) {
        case CelebrationDecision.seedSilently:
          await _watermark.mark(memberId, occurredAt);
        case CelebrationDecision.skip:
          break;
        case CelebrationDecision.fire:
          await _watermark.mark(memberId, occurredAt);
          navigator?.pushNamed(
            AppRoutes.postClassStreak,
            arguments: _dataFor(newest, occurredAt, history.history),
          );
      }
    } catch (e, st) {
      log('CelebrationDetector.maybeFire skipped', error: e, stackTrace: st);
    } finally {
      _inFlight = false;
    }
  }

  /// The attended row with the newest parseable `occurred_at`, or null.
  MemberClassHistoryRow? _newestAttended(List<MemberClassHistoryRow> rows) {
    MemberClassHistoryRow? best;
    DateTime? bestAt;
    for (final r in rows) {
      if (r.status != MemberClassHistoryStatus.attended) continue;
      final at = r.occurredAt == null ? null : DateTime.tryParse(r.occurredAt!);
      if (at == null) continue;
      if (bestAt == null || at.isAfter(bestAt)) {
        best = r;
        bestAt = at;
      }
    }
    return best;
  }

  CelebrationData _dataFor(
    MemberClassHistoryRow newest,
    DateTime occurredAt,
    List<MemberClassHistoryRow> rows,
  ) {
    final anchor = DateTime.tryParse(newest.originalDate) ?? occurredAt;
    final attended = <DateTime>[];
    for (final r in rows) {
      if (r.status != MemberClassHistoryStatus.attended) continue;
      final d = DateTime.tryParse(r.originalDate);
      if (d != null) attended.add(d);
    }
    return CelebrationData(
      className: newest.className,
      pointsWorth: newest.pointsWorth,
      occurredAt: occurredAt,
      completedWeekdayIndices:
          completedWeekdayIndices(anchorDate: anchor, attendedDates: attended),
    );
  }
}
