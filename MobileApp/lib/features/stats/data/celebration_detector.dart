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
///
/// [fireNow] is the second, DEBUG-ONLY entry point — the identity sheet's
/// Developer section forces the same flow open on demand. It reads the same
/// data but leaves the watermark untouched, so previewing the celebration can
/// never consume the real one.
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

  /// **Debug entry point.** Force the celebration flow open on demand, for the
  /// identity sheet's Developer section: it previews what a member sees when
  /// they tap the after-class push, without staging a real staff check-in.
  ///
  /// Same data path as [maybeFire] — class-history head → newest attended row
  /// → payload — but it IGNORES the watermark and, load-bearing, **never
  /// advances it**. A dev preview must not consume a real celebration that was
  /// about to be tested; only [maybeFire] is allowed to burn one.
  ///
  /// It always shows the flow: with no attended row yet (or a failed fetch) it
  /// falls back to a representative payload, because a dev trigger that
  /// silently does nothing on a fresh member is useless. The card CHAIN is not
  /// special-cased — `celebration_flow.dart` still composes it from the gym's
  /// real capability flags, so the preview is precisely what this gym's
  /// members would get.
  Future<void> fireNow(NavigatorState? navigator) async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      final data = await _liveData() ?? _debugFallbackData();
      navigator?.pushNamed(AppRoutes.postClassStreak, arguments: data);
    } finally {
      _inFlight = false;
    }
  }

  /// The newest attended class as a celebration payload, or null when no
  /// member is selected, nothing has been attended, or the fetch failed.
  /// [maybeFire] keeps its own read because it also needs the raw instant to
  /// compare against — and then advance — the watermark.
  Future<CelebrationData?> _liveData() async {
    final memberId = selectedMember.memberId;
    final gymId = selectedMember.gymId;
    if (memberId == null || gymId == null) return null;
    try {
      final history =
          await _history.getHistory(gymId: gymId, memberId: memberId);
      final newest = _newestAttended(history.history);
      if (newest == null) return null;
      final occurredAt = DateTime.tryParse(newest.occurredAt!);
      if (occurredAt == null) return null;
      return _dataFor(newest, occurredAt, history.history);
    } catch (e, st) {
      log('CelebrationDetector.fireNow history read failed',
          error: e, stackTrace: st);
      return null;
    }
  }

  /// DEBUG-ONLY stand-in payload so the flow stays previewable on a member who
  /// has never been checked in. Today's strip index is derived through the
  /// same Sunday-first [sundayStripIndex] rule the real payload uses, never a
  /// hardcoded literal.
  CelebrationData _debugFallbackData() {
    final now = DateTime.now();
    return CelebrationData(
      className: 'Muay Thai',
      pointsWorth: 10,
      occurredAt: now,
      completedWeekdayIndices: <int>[sundayStripIndex(now)],
    );
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
