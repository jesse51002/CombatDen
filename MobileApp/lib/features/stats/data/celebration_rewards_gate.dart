import 'dart:developer';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/rewards/data/models/reward_item.dart';
import 'package:mobile_app/features/rewards/data/repositories/member_rewards_repository.dart';

/// Whether the post-class rewards card is worth showing: the member can redeem
/// SOMETHING, or is within 10% of the cheapest reward.
///
/// `balance >= cheapest` implies `balance * 10 >= cheapest * 9`, so the
/// "anything affordable" clause collapses into the 90% clause — one
/// comparison, not two.
///
/// Integer maths on purpose: both sides are exact for every input, so the
/// boundary (900 of 1,000 must SHOW) can never turn on how `0.9 * cost`
/// happens to round. Points are whole numbers; nothing here needs a double.
bool rewardsCardWorthShowing({
  required int? balance,
  required Iterable<int> costs,
}) {
  if (costs.isEmpty) return false; // nothing to carousel
  if (balance == null) return true; // unknown -> show (the default-to-show law)
  final cheapest = costs.reduce(math.min);
  if (cheapest <= 0) return true; // a 0-cost reward is always redeemable
  return balance * 10 >= cheapest * 9;
}

/// The reward catalog the post-class flow decides on, fetched ONCE when the
/// celebration is pushed and reused by the card itself.
///
/// It holds only the CATALOG, never a decided boolean: the balance lives on
/// the shared `MemberProfileBloc` and is read fresh at decision time, so the
/// gate has exactly one responsibility and can never hold a stale balance.
///
/// It is a [ChangeNotifier] so a card whose CTA was built before the prime
/// landed re-derives its label and destination when it does — see
/// `points_screen.dart`.
class CelebrationRewardsGate extends ChangeNotifier {
  CelebrationRewardsGate._();

  /// The app-wide gate. `CelebrationDetector` primes it at flow-push time.
  static final CelebrationRewardsGate instance = CelebrationRewardsGate._();

  /// A standalone gate so a test never touches (or primes) the singleton.
  @visibleForTesting
  factory CelebrationRewardsGate.forTesting() => CelebrationRewardsGate._();

  List<RewardItem>? _catalog;

  /// The catalog, or null while the prime is in flight / after it failed.
  List<RewardItem>? get catalog => _catalog;

  /// The point costs, or null when undecided.
  Iterable<int>? get costs => _catalog?.map((r) => r.pointCost);

  /// Forget the previous celebration's catalog, so a second celebration in the
  /// same session can never decide on it.
  void reset() {
    _catalog = null;
    notifyListeners();
  }

  /// Fire-and-forget. Never throws: a failure leaves the gate undecided, which
  /// the flow reads as "show" (see `nextCelebrationCard`).
  Future<void> prime({MemberRewardsRepository? repository}) async {
    try {
      final gymId = selectedMember.gymId;
      final memberId = selectedMember.memberId;
      if (gymId == null || memberId == null) return;
      final repo = repository ?? MemberRewardsRepository(apiClient: ApiClient());
      _catalog = await repo.listCatalog(gymId: gymId, memberId: memberId);
      notifyListeners();
    } catch (e, st) {
      log('CelebrationRewardsGate.prime failed', error: e, stackTrace: st);
    }
  }
}
