import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/stats/data/celebration_data.dart';
import 'package:mobile_app/features/stats/data/celebration_flow.dart';
import 'package:mobile_app/features/stats/data/celebration_rewards_gate.dart';

import '../../../helpers/fake_rewards_catalog.dart';

Future<void> _selectGym({
  bool rankEnabled = true,
  bool hasRewards = true,
}) =>
    selectedMember.select(
      memberId: 'm1',
      gymId: 'g1',
      gymName: 'Global MMA',
      firstName: 'Jane',
      lastName: 'Doe',
      gymRankEnabled: rankEnabled,
      gymHasRewards: hasRewards,
    );

/// A class flow: `occurredAt` non-null is what `classAttended` reads.
CelebrationData _afterClass({bool promoted = false}) => CelebrationData(
      className: 'No-Gi Grappling',
      pointsWorth: 30,
      occurredAt: DateTime.utc(2026, 7, 23, 18),
      promoted: promoted,
    );

/// A promotion with no class behind it — the common shape, since staff work
/// the ready-to-promote board days after anyone trained.
const CelebrationData _promotionOnly = CelebrationData(promoted: true);

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    selectedMember.reset();
    // The gate is a process-wide singleton — a leaked catalog would decide the
    // next test's flow.
    CelebrationRewardsGate.instance.reset();
  });

  group('celebrationCardRoutes composes only the cards that apply', () {
    test('a gym with rewards and a ranked member gets all five', () {
      expect(
        celebrationCardRoutes(
          promoted: false,
          classAttended: true,
          hasRewards: true,
          rewardsWorthShowing: true,
          rankEnabled: true,
          hasRank: true,
        ),
        [
          AppRoutes.postClassStreak,
          AppRoutes.postClassPoints,
          AppRoutes.postClassRewards,
          AppRoutes.postClassRank,
          AppRoutes.postClassWins,
        ],
      );
    });

    test('no rewards drops the rewards card', () {
      expect(
        celebrationCardRoutes(
          promoted: false,
          classAttended: true,
          hasRewards: false,
          rewardsWorthShowing: true,
          rankEnabled: true,
          hasRank: true,
        ),
        [
          AppRoutes.postClassStreak,
          AppRoutes.postClassPoints,
          AppRoutes.postClassRank,
          AppRoutes.postClassWins,
        ],
      );
    });

    test('a member who can reach nothing drops the rewards card too', () {
      expect(
        celebrationCardRoutes(
          promoted: false,
          classAttended: true,
          hasRewards: true,
          rewardsWorthShowing: false,
          rankEnabled: true,
          hasRank: true,
        ),
        [
          AppRoutes.postClassStreak,
          AppRoutes.postClassPoints,
          AppRoutes.postClassRank,
          AppRoutes.postClassWins,
        ],
      );
    });

    test('ranks off drops the rank card even if a rank came back', () {
      expect(
        celebrationCardRoutes(
          promoted: false,
          classAttended: true,
          hasRewards: true,
          rewardsWorthShowing: true,
          rankEnabled: false,
          hasRank: true,
        ),
        [
          AppRoutes.postClassStreak,
          AppRoutes.postClassPoints,
          AppRoutes.postClassRewards,
          AppRoutes.postClassWins,
        ],
      );
    });

    test('a rank-enabled gym still drops the card for an UNGRADED member', () {
      expect(
        celebrationCardRoutes(
          promoted: false,
          classAttended: true,
          hasRewards: true,
          rewardsWorthShowing: true,
          rankEnabled: true,
          hasRank: false,
        ),
        [
          AppRoutes.postClassStreak,
          AppRoutes.postClassPoints,
          AppRoutes.postClassRewards,
          AppRoutes.postClassWins,
        ],
      );
    });

    test('the bare gym is streak + points + wins, and nothing else', () {
      expect(
        celebrationCardRoutes(
          promoted: false,
          classAttended: true,
          hasRewards: false,
          rewardsWorthShowing: false,
          rankEnabled: false,
          hasRank: false,
        ),
        [
          AppRoutes.postClassStreak,
          AppRoutes.postClassPoints,
          AppRoutes.postClassWins,
        ],
      );
    });
  });

  group('the promotion is card 0, and it suppresses the rank card', () {
    test('a promotion alone is the WHOLE flow, so its CTA says Done', () {
      final routes = celebrationCardRoutes(
        promoted: true,
        classAttended: false,
        hasRewards: true,
        rewardsWorthShowing: true,
        rankEnabled: true,
        hasRank: true,
      );
      expect(routes, [AppRoutes.promotion]);
    });

    test('a promotion PLUS a class opens on the belt and drops the rank card',
        () {
      expect(
        celebrationCardRoutes(
          promoted: true,
          classAttended: true,
          hasRewards: true,
          rewardsWorthShowing: true,
          rankEnabled: true,
          hasRank: true,
        ),
        [
          AppRoutes.promotion,
          AppRoutes.postClassStreak,
          AppRoutes.postClassPoints,
          AppRoutes.postClassRewards,
          // No `postClassRank` — one belt moment per app open, and its own
          // copy would say "N more classes until promotion" over a
          // classesSinceRank the promotion just reset to 0.
          AppRoutes.postClassWins,
        ],
      );
    });

    test('the rank card comes BACK on the same class flow with no promotion',
        () {
      final routes = celebrationCardRoutes(
        promoted: false,
        classAttended: true,
        hasRewards: true,
        rewardsWorthShowing: true,
        rankEnabled: true,
        hasRank: true,
      );
      expect(routes, contains(AppRoutes.postClassRank));
      expect(routes, isNot(contains(AppRoutes.promotion)));
    });

    test('a gym with ranks OFF never shows the promotion card', () {
      expect(
        celebrationCardRoutes(
          promoted: true,
          classAttended: false,
          hasRewards: true,
          rewardsWorthShowing: true,
          rankEnabled: false,
          hasRank: true,
        ),
        isEmpty,
      );
    });

    test('nothing pending composes to an EMPTY flow', () {
      expect(
        celebrationCardRoutes(
          promoted: false,
          classAttended: false,
          hasRewards: true,
          rewardsWorthShowing: true,
          rankEnabled: true,
          hasRank: true,
        ),
        isEmpty,
      );
    });
  });

  group('no class attended means NO class card, wins included', () {
    test('the four class cards are gated as one group', () {
      final routes = celebrationCardRoutes(
        promoted: true,
        classAttended: false,
        hasRewards: true,
        rewardsWorthShowing: true,
        rankEnabled: true,
        hasRank: true,
      );
      // Streak and points would show a stale week and `+0 points`; the wins
      // recap recaps a class and ends on "book your next class". The wins case
      // is the easy one to forget — it is unconditional INSIDE a class flow.
      expect(routes, isNot(contains(AppRoutes.postClassStreak)));
      expect(routes, isNot(contains(AppRoutes.postClassPoints)));
      expect(routes, isNot(contains(AppRoutes.postClassRewards)));
      expect(routes, isNot(contains(AppRoutes.postClassRank)));
      expect(routes, isNot(contains(AppRoutes.postClassWins)));
    });

    test('a promotion-only flow does not chain into the class cards', () async {
      await _selectGym();
      expect(
        nextCelebrationCard(
          current: AppRoutes.promotion,
          data: _promotionOnly,
          hasRank: true,
          pointsBalance: 120,
        ),
        isNull,
      );
      expect(celebrationCtaLabel(null), 'Done');
    });
  });

  group('the wins card closes EVERY gym shape that had a class', () {
    test('it is present and LAST for all four rank/rewards combinations', () {
      for (final rankEnabled in [true, false]) {
        for (final hasRewards in [true, false]) {
          final routes = celebrationCardRoutes(
            promoted: false,
            classAttended: true,
            hasRewards: hasRewards,
            rewardsWorthShowing: true,
            rankEnabled: rankEnabled,
            hasRank: rankEnabled,
          );
          final shape = 'rank=$rankEnabled rewards=$hasRewards';
          expect(routes, contains(AppRoutes.postClassWins), reason: shape);
          expect(routes.last, AppRoutes.postClassWins, reason: shape);
          // Exactly once — the ungated entry can't be duplicated by a gym flag
          // the way a conditional card could.
          expect(
            routes.where((r) => r == AppRoutes.postClassWins).length,
            1,
            reason: shape,
          );
        }
      }
    });

    test('an unreachable reward catalog still ends on wins', () {
      final routes = celebrationCardRoutes(
        promoted: false,
        classAttended: true,
        hasRewards: true,
        rewardsWorthShowing: false,
        rankEnabled: false,
        hasRank: false,
      );
      expect(routes.last, AppRoutes.postClassWins);
    });

    test('a promotion in front of a class flow still ends on wins', () {
      final routes = celebrationCardRoutes(
        promoted: true,
        classAttended: true,
        hasRewards: false,
        rewardsWorthShowing: false,
        rankEnabled: true,
        hasRank: true,
      );
      expect(routes.first, AppRoutes.promotion);
      expect(routes.last, AppRoutes.postClassWins);
    });
  });

  group('nextCelebrationCard never chains into a skipped card', () {
    test('the full flow steps through every card in order', () async {
      await _selectGym();
      final data = _afterClass();

      expect(
        nextCelebrationCard(
          current: AppRoutes.postClassStreak,
          data: data,
          hasRank: true,
          pointsBalance: 120,
        ),
        AppRoutes.postClassPoints,
      );
      expect(
        nextCelebrationCard(
          current: AppRoutes.postClassPoints,
          data: data,
          hasRank: true,
          pointsBalance: 120,
        ),
        AppRoutes.postClassRewards,
      );
      expect(
        nextCelebrationCard(
          current: AppRoutes.postClassRewards,
          data: data,
          hasRank: true,
          pointsBalance: 120,
        ),
        AppRoutes.postClassRank,
      );
      expect(
        nextCelebrationCard(
          current: AppRoutes.postClassRank,
          data: data,
          hasRank: true,
          pointsBalance: 120,
        ),
        AppRoutes.postClassWins,
      );
    });

    test('a promotion hands off to the streak card when a class is pending',
        () async {
      await _selectGym();
      final data = _afterClass(promoted: true);

      expect(
        nextCelebrationCard(
          current: AppRoutes.promotion,
          data: data,
          hasRank: true,
          pointsBalance: 120,
        ),
        AppRoutes.postClassStreak,
      );
      // …and the rewards card then ends on WINS, never on the rank card the
      // promotion composed out.
      expect(
        nextCelebrationCard(
          current: AppRoutes.postClassRewards,
          data: data,
          hasRank: true,
          pointsBalance: 120,
        ),
        AppRoutes.postClassWins,
      );
    });

    test('no rewards sends points STRAIGHT to rank', () async {
      await _selectGym(hasRewards: false);

      expect(
        nextCelebrationCard(
          current: AppRoutes.postClassPoints,
          data: _afterClass(),
          hasRank: true,
          pointsBalance: 120,
        ),
        AppRoutes.postClassRank,
      );
    });

    test('whichever card is second-to-last now hands off to WINS', () async {
      // The tail moved: every card that used to end the flow now continues
      // into the wins recap instead of saying "Done".
      await _selectGym();
      expect(
        nextCelebrationCard(
          current: AppRoutes.postClassRank,
          data: _afterClass(),
          hasRank: true,
          pointsBalance: 120,
        ),
        AppRoutes.postClassWins,
      );

      // Ranks off: rewards is second-to-last.
      await _selectGym(rankEnabled: false);
      expect(
        nextCelebrationCard(
          current: AppRoutes.postClassRewards,
          data: _afterClass(),
          hasRank: true,
          pointsBalance: 120,
        ),
        AppRoutes.postClassWins,
      );

      // The emptiest gym: points is second-to-last.
      await _selectGym(rankEnabled: false, hasRewards: false);
      expect(
        nextCelebrationCard(
          current: AppRoutes.postClassPoints,
          data: _afterClass(),
          hasRank: false,
          pointsBalance: 120,
        ),
        AppRoutes.postClassWins,
      );
    });

    test('WINS is the last card, so nothing follows it', () async {
      await _selectGym();
      expect(
        nextCelebrationCard(
          current: AppRoutes.postClassWins,
          data: _afterClass(),
          hasRank: true,
          pointsBalance: 120,
        ),
        isNull,
      );

      await _selectGym(rankEnabled: false, hasRewards: false);
      expect(
        nextCelebrationCard(
          current: AppRoutes.postClassWins,
          data: _afterClass(),
          hasRank: false,
          pointsBalance: 120,
        ),
        isNull,
      );
    });

    test('a card that is not in this gym\'s flow ends it rather than guessing',
        () async {
      await _selectGym(rankEnabled: false);

      // A PR-3 deep link can land on a card the composed flow skipped.
      expect(
        nextCelebrationCard(
          current: AppRoutes.postClassRank,
          data: _afterClass(),
          hasRank: true,
          pointsBalance: 120,
        ),
        isNull,
      );
    });

    test('an argument-less card degrades to Done, promotion included',
        () async {
      await _selectGym();
      // `CelebrationData.empty()` is what a card entered with no arguments
      // falls back to: no promotion, no class, so the list is empty.
      for (final route in [
        AppRoutes.promotion,
        AppRoutes.postClassStreak,
        AppRoutes.postClassWins,
      ]) {
        expect(
          nextCelebrationCard(
            current: route,
            data: const CelebrationData.empty(),
            hasRank: true,
            pointsBalance: 120,
          ),
          isNull,
          reason: route,
        );
      }
    });
  });

  group('the affordability gate decides the rewards card', () {
    test('an UNDECIDED gate shows the card — the default-to-show law',
        () async {
      await _selectGym();

      // Nothing primed: the prime is still in flight, or it failed.
      expect(CelebrationRewardsGate.instance.costs, isNull);
      expect(
        nextCelebrationCard(
          current: AppRoutes.postClassPoints,
          data: _afterClass(),
          hasRank: true,
          pointsBalance: 0,
        ),
        AppRoutes.postClassRewards,
      );
    });

    test('a member 90% of the way to the cheapest still gets the card',
        () async {
      await _selectGym();
      await primeRewardsGate([1000, 5000]);

      expect(
        nextCelebrationCard(
          current: AppRoutes.postClassPoints,
          data: _afterClass(),
          hasRank: true,
          pointsBalance: 900,
        ),
        AppRoutes.postClassRewards,
      );
    });

    test('one point short of 90% skips it: points goes straight to rank',
        () async {
      await _selectGym();
      await primeRewardsGate([1000, 5000]);

      expect(
        nextCelebrationCard(
          current: AppRoutes.postClassPoints,
          data: _afterClass(),
          hasRank: true,
          pointsBalance: 899,
        ),
        AppRoutes.postClassRank,
      );
    });

    test('an unreachable catalog sends points past rewards to WINS', () async {
      await _selectGym(rankEnabled: false);
      await primeRewardsGate([1000]);

      expect(
        nextCelebrationCard(
          current: AppRoutes.postClassPoints,
          data: _afterClass(),
          hasRank: true,
          pointsBalance: 10,
        ),
        AppRoutes.postClassWins,
      );
    });

    test('a decided-EMPTY catalog skips the card', () async {
      await _selectGym();
      await primeRewardsGate([]);

      expect(
        nextCelebrationCard(
          current: AppRoutes.postClassPoints,
          data: _afterClass(),
          hasRank: true,
          pointsBalance: 9999,
        ),
        AppRoutes.postClassRank,
      );
    });

    test('a null balance shows the card rather than assuming zero', () async {
      await _selectGym();
      await primeRewardsGate([5000]);

      expect(
        nextCelebrationCard(
          current: AppRoutes.postClassPoints,
          data: _afterClass(),
          hasRank: true,
          pointsBalance: null,
        ),
        AppRoutes.postClassRewards,
      );
    });
  });

  group('celebrationCtaLabel', () {
    test('the last card says Done, every other one says Continue', () {
      expect(celebrationCtaLabel(null), 'Done');
      expect(celebrationCtaLabel(AppRoutes.postClassRank), 'Continue');
    });
  });
}
