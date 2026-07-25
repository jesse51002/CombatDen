import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_plan_rules.dart';

/// **The wizard's plan block must be the backend's plan block, nothing wider.**
///
/// `FastApiBackend/src/memberships/sql/member_memberships_check_existing.sql`
/// is the whole duplicate guard the API actually enforces:
///
/// ```sql
/// AND mms.plan_id = ANY(:plan_ids)
/// AND mms.status IN ('active', 'frozen')
/// AND mp.plan_type = 'recurring'
/// ```
///
/// Recurring only, per plan. Every other combination is a sale the backend takes
/// — one_time and trial packs are allowed to STACK, and a member on one
/// recurring plan may buy a different one. The wizard used to refuse any
/// non-one_time plan at `active` / `trial` / `frozen` / `overdue`, so it turned
/// away money the API would have accepted, with no override anywhere in the
/// flow. The kiosk derives its own block from the same SQL
/// (`KioskSignupState.planBlockReasonFor`), so these cases are also what keeps
/// the two clients stating one rule instead of two.
///
/// **The status list does not translate string-for-string, and that is the
/// subtle case below.** The guard reads `member_memberships_status`, whose
/// `CASE` emits only `cancelled` / `ended` / `frozen` / `active` — never
/// `overdue`. A past-due membership is plain `active` there, and the client's
/// `overdue` is a DISPLAY status the backend derives from exactly such a row.
/// So `{active, frozen, overdue}` on the client IS `('active','frozen')` on the
/// server; a literal string mirror would UNDER-block and offer a member their
/// own plan back while they are in arrears on it.
void main() {
  MembershipInfo membership({
    required String planId,
    required String? planType,
    required MembershipStatus status,
  }) =>
      MembershipInfo(
        planId: planId,
        planName: planId,
        planType: planType,
        status: status,
        itemId: 'item-$planId',
        paidByMemberId: 'member-1',
        baseCost: 10000,
        durationAmount: 1,
        durationUnit: 'month',
        totalPrice: 10000,
        startDate: DateTime.utc(2026, 1, 1),
      );

  group('disabledPlanReasons blocks exactly what the backend rejects', () {
    test('a same-plan RECURRING membership at active is blocked', () {
      final reasons = disabledPlanReasons([
        membership(
          planId: 'unlimited',
          planType: 'recurring',
          status: MembershipStatus.active,
        ),
      ]);

      expect(reasons, {'unlimited': 'Already on this plan'});
    });

    test('a same-plan RECURRING membership at frozen is blocked', () {
      final reasons = disabledPlanReasons([
        membership(
          planId: 'unlimited',
          planType: 'recurring',
          status: MembershipStatus.frozen,
        ),
      ]);

      expect(reasons.keys, ['unlimited']);
    });

    test('a same-plan RECURRING membership at OVERDUE is blocked', () {
      final reasons = disabledPlanReasons([
        membership(
          planId: 'unlimited',
          planType: 'recurring',
          status: MembershipStatus.overdue,
        ),
      ]);

      // `overdue` is not a backend status: this row is `active` in the view the
      // guard reads, so the API WOULD reject the start. Allowing it here would
      // hand staff a plan tile that fails at the money step.
      expect(reasons, {'unlimited': 'Already on this plan'});
    });

    test('an OVERDUE one-time pack still never blocks', () {
      // The status half of the rule is only reached for a recurring plan — the
      // `plan_type` filter comes first, so a past-due pack is irrelevant.
      final reasons = disabledPlanReasons([
        membership(
          planId: 'ten-pack',
          planType: 'one_time',
          status: MembershipStatus.overdue,
        ),
      ]);

      expect(reasons, isEmpty);
    });

    test('the block is PER PLAN — a different recurring plan stays open', () {
      final reasons = disabledPlanReasons([
        membership(
          planId: 'unlimited',
          planType: 'recurring',
          status: MembershipStatus.active,
        ),
      ]);

      // `mms.plan_id = ANY(:plan_ids)`: holding one recurring plan says nothing
      // about any other, and an upsell is the most valuable sale on the board.
      expect(reasons.containsKey('kids-monthly'), isFalse);
    });

    test('a TRIAL plan at active is now ALLOWED — the API takes that sale', () {
      final reasons = disabledPlanReasons([
        membership(
          planId: 'week-trial',
          planType: 'trial',
          status: MembershipStatus.active,
        ),
      ]);

      // `mp.plan_type = 'recurring'` is the SQL's own filter: trial packs stack,
      // and granting a repeat trial is exactly what staff do at a desk. The old
      // predicate blocked this outright.
      expect(reasons, isEmpty);
    });

    test('a TRIAL plan at the derived trial status is allowed too', () {
      final reasons = disabledPlanReasons([
        membership(
          planId: 'week-trial',
          planType: 'trial',
          status: MembershipStatus.trial,
        ),
      ]);

      expect(reasons, isEmpty);
    });

    test('a ONE-TIME pack never blocks its own plan', () {
      final reasons = disabledPlanReasons([
        membership(
          planId: 'ten-pack',
          planType: 'one_time',
          status: MembershipStatus.active,
        ),
      ]);

      expect(reasons, isEmpty);
    });

    test('a terminal recurring membership never blocks', () {
      final reasons = disabledPlanReasons([
        membership(
          planId: 'unlimited',
          planType: 'recurring',
          status: MembershipStatus.cancelled,
        ),
        membership(
          planId: 'kids-monthly',
          planType: 'recurring',
          status: MembershipStatus.ended,
        ),
      ]);

      expect(reasons, isEmpty);
    });

    test('a null plan_type is treated as not-recurring, so it never blocks',
        () {
      // `planType` is nullable on the wire; only an explicit `recurring` may
      // close a plan, so an unknown type fails OPEN rather than refusing a sale
      // on a guess.
      final reasons = disabledPlanReasons([
        membership(
          planId: 'mystery',
          planType: null,
          status: MembershipStatus.active,
        ),
      ]);

      expect(reasons, isEmpty);
    });

    test('mixed history blocks only the held recurring plan', () {
      final reasons = disabledPlanReasons([
        membership(
          planId: 'unlimited',
          planType: 'recurring',
          status: MembershipStatus.active,
        ),
        membership(
          planId: 'ten-pack',
          planType: 'one_time',
          status: MembershipStatus.active,
        ),
        membership(
          planId: 'week-trial',
          planType: 'trial',
          status: MembershipStatus.active,
        ),
      ]);

      expect(reasons.keys, ['unlimited']);
    });

    test('no memberships blocks nothing', () {
      expect(disabledPlanReasons(const []), isEmpty);
    });
  });

  group('the surrounding rules are untouched', () {
    test('currentMembershipsForParticipant still lists every live membership',
        () {
      // The wizard still SHOWS what the member holds in its "Already has"
      // block, so relaxing the block did not also hide the information — a
      // trial that no longer blocks its own plan is still on screen.
      final live = currentMembershipsForParticipant([
        membership(
          planId: 'week-trial',
          planType: 'trial',
          status: MembershipStatus.active,
        ),
        membership(
          planId: 'gone',
          planType: 'recurring',
          status: MembershipStatus.ended,
        ),
      ], 'member-1');

      expect(live.map((m) => m.planId), ['week-trial']);
    });

    test('warningPlanReasons still soft-notes a finished trial', () {
      final warnings = warningPlanReasons([
        membership(
          planId: 'week-trial',
          planType: 'trial',
          status: MembershipStatus.ended,
        ),
      ]);

      expect(warnings, {'week-trial': 'Had this trial in the past'});
    });
  });
}
