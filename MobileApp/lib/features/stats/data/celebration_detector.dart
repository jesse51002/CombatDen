import 'dart:async';
import 'dart:developer';

import 'package:flutter/widgets.dart';

import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/home/data/models/class_history.dart';
import 'package:mobile_app/features/home/data/repositories/member_class_history_repository.dart';
import 'package:mobile_app/features/profile/data/models/member_profile.dart';
import 'package:mobile_app/features/stats/data/celebration_data.dart';
import 'package:mobile_app/features/stats/data/celebration_flow.dart';
import 'package:mobile_app/features/stats/data/celebration_rewards_gate.dart';
import 'package:mobile_app/features/stats/data/celebration_rules.dart';
import 'package:mobile_app/features/stats/data/celebration_watermark.dart';
import 'package:mobile_app/features/stats/data/promotion_rules.dart';
import 'package:mobile_app/features/stats/data/promotion_watermark.dart';

/// Watches the app-open path for the two things worth taking over the screen —
/// a belt promotion the member hasn't seen, and a fresh staff check-in — and
/// pushes the composed celebration flow ONCE.
///
/// The two legs are INDEPENDENT by design. A promotion is staff-driven from
/// the ready-to-promote board, minutes to days after a class and often in
/// bulk, so it rides the profile the app already loaded and needs no network
/// call of its own; the class leg reads the class-history head. Each leg has
/// its own watermark and its own failure handling — a class-history fetch
/// failure must not swallow a promotion that needed no network at all.
///
/// Decoupled + failure-safe throughout: a fetch failure logs and skips — it
/// never crashes or blocks the home screen. Both watermarks advance BEFORE the
/// flow is shown, so a celebration fires exactly once and never replays, even
/// if the app is killed mid-flow.
///
/// [fireNow] is the second, DEBUG-ONLY entry point — the identity sheet's
/// Developer section forces the class flow open on demand. It reads the same
/// data but leaves the watermark untouched, so previewing the celebration can
/// never consume the real one.
class CelebrationDetector {
  CelebrationDetector({
    MemberClassHistoryRepository? historyRepository,
    CelebrationWatermark watermark = const CelebrationWatermark(),
    PromotionWatermark promotionWatermark = const PromotionWatermark(),
    CelebrationRewardsGate? rewardsGate,
  })  : _history = historyRepository ??
            MemberClassHistoryRepository(apiClient: ApiClient()),
        _watermark = watermark,
        _promotionWatermark = promotionWatermark,
        _rewardsGate = rewardsGate ?? CelebrationRewardsGate.instance;

  final MemberClassHistoryRepository _history;
  final CelebrationWatermark _watermark;
  final PromotionWatermark _promotionWatermark;
  final CelebrationRewardsGate _rewardsGate;

  /// Guards against overlapping fetches (two foregrounds in quick succession).
  bool _inFlight = false;

  /// Start the reward-catalog read the flow's rewards gate decides on, one
  /// full card before the answer is needed (the points card is the one whose
  /// CTA pushes the rewards card). [CelebrationRewardsGate.reset] first, so a
  /// second celebration in the same session never decides on the previous
  /// one's catalog; the prime never throws, and an unfinished one simply
  /// leaves the gate undecided, which reads as "show".
  void _primeRewards() {
    _rewardsGate.reset();
    unawaited(_rewardsGate.prime());
  }

  /// Decide both legs against [profile] (the loaded member profile — the
  /// promotion rides it) plus the class-history head, compose the flow, and
  /// push its first card onto [navigator]. Safe to call on every app open /
  /// foreground; a no-op when no member is selected or nothing is pending.
  Future<void> maybeFire(NavigatorState? navigator, MemberProfile? profile) async {
    if (_inFlight) return;
    final memberId = selectedMember.memberId;
    final gymId = selectedMember.gymId;
    if (memberId == null || gymId == null) return;
    _inFlight = true;
    try {
      final promoted = await _decidePromotion(memberId, profile);

      // The class leg gets its OWN try/catch rather than sharing the outer
      // one: a class-history failure must degrade to "no class attended", not
      // swallow a promotion that was already decided without any network.
      CelebrationData? classData;
      try {
        classData = await _classCelebrationData(
          gymId: gymId,
          memberId: memberId,
          promoted: promoted,
        );
      } catch (e, st) {
        log('CelebrationDetector class leg skipped', error: e, stackTrace: st);
      }
      final classAttended = classData != null;

      final routes = celebrationCardRoutes(
        promoted: promoted,
        classAttended: classAttended,
        hasRewards: selectedMember.gymHasRewards,
        // The gate is reset-and-primed a line below, so it is UNDECIDED at
        // this instant — which reads as show, per the default-to-show law.
        // It can't change the FIRST card either way; the cards themselves
        // re-derive their successor from the primed gate.
        rewardsWorthShowing: true,
        rankEnabled: selectedMember.gymRankEnabled,
        hasRank: profile?.rank != null,
      );
      if (routes.isEmpty) return;

      // Only a class flow can reach the rewards card, so a promotion-only
      // flow doesn't fire a catalog fetch it will never read.
      if (classAttended) _primeRewards();

      navigator?.pushNamed(
        routes.first,
        arguments: classData ?? CelebrationData(promoted: promoted),
      );
    } catch (e, st) {
      log('CelebrationDetector.maybeFire skipped', error: e, stackTrace: st);
    } finally {
      _inFlight = false;
    }
  }

  /// The promotion leg: decide against the profile the app already loaded — no
  /// network call at all. True only when a promotion should be CELEBRATED.
  ///
  /// At a gym with ranks off the watermark is deliberately left ALONE: there
  /// is no rank surface, so there is nothing to have been seen. If the gym
  /// turns ranks back on, the member's most recent promotion is celebrated
  /// once at that point — which is the app introducing them to the ladder they
  /// are now on.
  Future<bool> _decidePromotion(String memberId, MemberProfile? profile) async {
    if (!selectedMember.gymRankEnabled) return false;
    try {
      final promotion = profile?.latestPromotion;
      final decision = decidePromotion(
        lastSeenActivityId: await _promotionWatermark.lastSeen(memberId),
        activityId: promotion?.activityId,
      );
      switch (decision) {
        case PromotionDecision.skip:
          return false;
        case PromotionDecision.seedSilently:
          await _promotionWatermark.mark(memberId, promotion!.activityId);
          return false;
        case PromotionDecision.fire:
          await _promotionWatermark.mark(memberId, promotion!.activityId);
          // A row with nothing to say is MARKED and not shown. Marking rather
          // than skipping is what guarantees an unrenderable row can never be
          // reconsidered on a later open.
          return (promotion.newRankName ?? '').trim().isNotEmpty;
      }
    } catch (e, st) {
      log('CelebrationDetector promotion leg skipped',
          error: e, stackTrace: st);
      return false;
    }
  }

  /// The class leg: the class-history head under the celebration watermark.
  /// Returns the payload when a fresh, unseen attendance should be celebrated,
  /// and null when there is nothing new to say (nothing attended, already
  /// seen, or the watermark was just seeded).
  Future<CelebrationData?> _classCelebrationData({
    required String gymId,
    required String memberId,
    required bool promoted,
  }) async {
    final history = await _history.getHistory(gymId: gymId, memberId: memberId);
    final newest = _newestAttended(history.history);
    if (newest == null) return null;
    final occurredAt = DateTime.tryParse(newest.occurredAt!);
    if (occurredAt == null) return null;

    final decision = decideCelebration(
      lastSeen: await _watermark.lastSeen(memberId),
      newestAttended: occurredAt,
    );
    switch (decision) {
      case CelebrationDecision.seedSilently:
        await _watermark.mark(memberId, occurredAt);
        return null;
      case CelebrationDecision.skip:
        return null;
      case CelebrationDecision.fire:
        await _watermark.mark(memberId, occurredAt);
        return _dataFor(
          newest,
          occurredAt,
          history.history,
          promoted: promoted,
        );
    }
  }

  /// **Debug entry point.** Force the class celebration flow open on demand,
  /// for the identity sheet's Developer section: it previews what a member sees
  /// when they tap the after-class push, without staging a real staff check-in.
  ///
  /// Same data path as [maybeFire]'s class leg — class-history head → newest
  /// attended row → payload — but it IGNORES the watermark and, load-bearing,
  /// **never advances it**. A dev preview must not consume a real celebration
  /// that was about to be tested; only [maybeFire] is allowed to burn one. The
  /// promotion has its own Developer row for the same reason.
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
      _primeRewards();
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
      return _dataFor(newest, occurredAt, history.history, promoted: false);
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
    List<MemberClassHistoryRow> rows, {
    required bool promoted,
  }) {
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
      promoted: promoted,
    );
  }
}
