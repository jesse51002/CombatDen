import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/stats/data/celebration_rewards_gate.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() => selectedMember.reset());

  group('rewardsCardWorthShowing', () {
    test('an empty catalog is never worth a card', () {
      expect(rewardsCardWorthShowing(balance: 9999, costs: const []), isFalse);
    });

    test('an unknown balance SHOWS — the default-to-show law', () {
      expect(rewardsCardWorthShowing(balance: null, costs: const [5000]),
          isTrue);
    });

    test('a free reward is always redeemable', () {
      expect(rewardsCardWorthShowing(balance: 0, costs: const [0, 900]),
          isTrue);
    });

    test('anything affordable shows', () {
      expect(rewardsCardWorthShowing(balance: 1200, costs: const [1000]),
          isTrue);
    });

    test('EXACTLY 90% of the cheapest shows — the boundary is inclusive', () {
      // The founder's rule is "unless they are 90% to one", so the member who
      // is exactly there is IN. The predicate compares integers so this can
      // never turn on how `0.9 * cost` rounds.
      expect(rewardsCardWorthShowing(balance: 900, costs: const [1000]),
          isTrue);
      expect(rewardsCardWorthShowing(balance: 9, costs: const [10]), isTrue);
      expect(rewardsCardWorthShowing(balance: 2700, costs: const [3000]),
          isTrue);
    });

    test('one point under 90% does not', () {
      expect(rewardsCardWorthShowing(balance: 899, costs: const [1000]),
          isFalse);
    });

    test('the CHEAPEST decides, whatever order the costs arrive in', () {
      // The backend orders cheapest-first, but the predicate must not depend
      // on it — a future ordering change can't be allowed to skip the card.
      expect(rewardsCardWorthShowing(balance: 900, costs: const [5000, 1000]),
          isTrue);
      expect(rewardsCardWorthShowing(balance: 899, costs: const [5000, 1000]),
          isFalse);
    });
  });

  group('CelebrationRewardsGate', () {
    test('starts and resets UNDECIDED, which the flow reads as show', () {
      final gate = CelebrationRewardsGate.forTesting();

      expect(gate.catalog, isNull);
      expect(gate.costs, isNull);

      gate.reset();
      expect(gate.costs, isNull);
    });

    test('a prime with no selected member leaves it undecided, not thrown',
        () async {
      final gate = CelebrationRewardsGate.forTesting();

      await gate.prime();

      expect(gate.catalog, isNull);
    });
  });
}
