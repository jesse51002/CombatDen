import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/state/selected_member.dart';
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
    test('a gym with rewards and a ranked member gets all four', () {
      expect(
        celebrationCardRoutes(
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
        ],
      );
    });

    test('no rewards drops the rewards card', () {
      expect(
        celebrationCardRoutes(
          hasRewards: false,
          rewardsWorthShowing: true,
          rankEnabled: true,
          hasRank: true,
        ),
        [
          AppRoutes.postClassStreak,
          AppRoutes.postClassPoints,
          AppRoutes.postClassRank,
        ],
      );
    });

    test('a member who can reach nothing drops the rewards card too', () {
      expect(
        celebrationCardRoutes(
          hasRewards: true,
          rewardsWorthShowing: false,
          rankEnabled: true,
          hasRank: true,
        ),
        [
          AppRoutes.postClassStreak,
          AppRoutes.postClassPoints,
          AppRoutes.postClassRank,
        ],
      );
    });

    test('ranks off drops the rank card even if a rank came back', () {
      expect(
        celebrationCardRoutes(
          hasRewards: true,
          rewardsWorthShowing: true,
          rankEnabled: false,
          hasRank: true,
        ),
        [
          AppRoutes.postClassStreak,
          AppRoutes.postClassPoints,
          AppRoutes.postClassRewards,
        ],
      );
    });

    test('a rank-enabled gym still drops the card for an UNGRADED member', () {
      expect(
        celebrationCardRoutes(
          hasRewards: true,
          rewardsWorthShowing: true,
          rankEnabled: true,
          hasRank: false,
        ),
        [
          AppRoutes.postClassStreak,
          AppRoutes.postClassPoints,
          AppRoutes.postClassRewards,
        ],
      );
    });

    test('the bare gym is streak + points, and nothing else', () {
      expect(
        celebrationCardRoutes(
          hasRewards: false,
          rewardsWorthShowing: false,
          rankEnabled: false,
          hasRank: false,
        ),
        [AppRoutes.postClassStreak, AppRoutes.postClassPoints],
      );
    });
  });

  group('nextCelebrationCard never chains into a skipped card', () {
    test('the full flow steps through every card in order', () async {
      await _selectGym();

      expect(
        nextCelebrationCard(
          current: AppRoutes.postClassStreak,
          hasRank: true,
          pointsBalance: 120,
        ),
        AppRoutes.postClassPoints,
      );
      expect(
        nextCelebrationCard(
          current: AppRoutes.postClassPoints,
          hasRank: true,
          pointsBalance: 120,
        ),
        AppRoutes.postClassRewards,
      );
      expect(
        nextCelebrationCard(
          current: AppRoutes.postClassRewards,
          hasRank: true,
          pointsBalance: 120,
        ),
        AppRoutes.postClassRank,
      );
    });

    test('no rewards sends points STRAIGHT to rank', () async {
      await _selectGym(hasRewards: false);

      expect(
        nextCelebrationCard(
          current: AppRoutes.postClassPoints,
          hasRank: true,
          pointsBalance: 120,
        ),
        AppRoutes.postClassRank,
      );
    });

    test('the LAST card returns null so its CTA can end the flow', () async {
      await _selectGym();
      expect(
        nextCelebrationCard(
          current: AppRoutes.postClassRank,
          hasRank: true,
          pointsBalance: 120,
        ),
        isNull,
      );

      // Ranks off: rewards is now the last card — it must NOT hand off to the
      // rank screen, which would paint a blank frame and bounce home.
      await _selectGym(rankEnabled: false);
      expect(
        nextCelebrationCard(
          current: AppRoutes.postClassRewards,
          hasRank: true,
          pointsBalance: 120,
        ),
        isNull,
      );

      // The emptiest gym: points is the last card.
      await _selectGym(rankEnabled: false, hasRewards: false);
      expect(
        nextCelebrationCard(
          current: AppRoutes.postClassPoints,
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
          hasRank: true,
          pointsBalance: 120,
        ),
        isNull,
      );
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
          hasRank: true,
          pointsBalance: 899,
        ),
        AppRoutes.postClassRank,
      );
    });

    test('an unreachable catalog makes POINTS the last card at a rank-off gym',
        () async {
      await _selectGym(rankEnabled: false);
      await primeRewardsGate([1000]);

      expect(
        nextCelebrationCard(
          current: AppRoutes.postClassPoints,
          hasRank: true,
          pointsBalance: 10,
        ),
        isNull,
      );
    });

    test('a decided-EMPTY catalog skips the card', () async {
      await _selectGym();
      await primeRewardsGate([]);

      expect(
        nextCelebrationCard(
          current: AppRoutes.postClassPoints,
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
