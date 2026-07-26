import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/stats/data/celebration_flow.dart';

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

  tearDown(() => selectedMember.reset());

  group('celebrationCardRoutes composes only the cards that apply', () {
    test('a gym with rewards and a ranked member gets all four', () {
      expect(
        celebrationCardRoutes(
          hasRewards: true,
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
        nextCelebrationCard(current: AppRoutes.postClassStreak, hasRank: true),
        AppRoutes.postClassPoints,
      );
      expect(
        nextCelebrationCard(current: AppRoutes.postClassPoints, hasRank: true),
        AppRoutes.postClassRewards,
      );
      expect(
        nextCelebrationCard(current: AppRoutes.postClassRewards, hasRank: true),
        AppRoutes.postClassRank,
      );
    });

    test('no rewards sends points STRAIGHT to rank', () async {
      await _selectGym(hasRewards: false);

      expect(
        nextCelebrationCard(current: AppRoutes.postClassPoints, hasRank: true),
        AppRoutes.postClassRank,
      );
    });

    test('the LAST card returns null so its CTA can end the flow', () async {
      await _selectGym();
      expect(
        nextCelebrationCard(current: AppRoutes.postClassRank, hasRank: true),
        isNull,
      );

      // Ranks off: rewards is now the last card — it must NOT hand off to the
      // rank screen, which would paint a blank frame and bounce home.
      await _selectGym(rankEnabled: false);
      expect(
        nextCelebrationCard(current: AppRoutes.postClassRewards, hasRank: true),
        isNull,
      );

      // The emptiest gym: points is the last card.
      await _selectGym(rankEnabled: false, hasRewards: false);
      expect(
        nextCelebrationCard(current: AppRoutes.postClassPoints, hasRank: false),
        isNull,
      );
    });

    test('a card that is not in this gym\'s flow ends it rather than guessing',
        () async {
      await _selectGym(rankEnabled: false);

      // A PR-3 deep link can land on a card the composed flow skipped.
      expect(
        nextCelebrationCard(current: AppRoutes.postClassRank, hasRank: true),
        isNull,
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
