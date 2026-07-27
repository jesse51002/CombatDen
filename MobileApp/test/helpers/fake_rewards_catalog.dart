import 'package:mobile_app/features/rewards/data/models/reward_item.dart';
import 'package:mobile_app/features/rewards/data/repositories/member_rewards_repository.dart';
import 'package:mobile_app/features/stats/data/celebration_rewards_gate.dart';

/// A reward catalog the celebration's gate can be primed from, without a
/// backend. [prime] is the gate's ONLY writer, so a test that needs a decided
/// gate has to go through a repository.
class FakeRewardsCatalog implements MemberRewardsRepository {
  FakeRewardsCatalog(this.pointCosts);

  final List<int> pointCosts;

  @override
  Future<List<RewardItem>> listCatalog({
    required String gymId,
    required String memberId,
  }) async =>
      [
        for (var i = 0; i < pointCosts.length; i++)
          rewardItem(cost: pointCosts[i], index: i),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// One catalog row. Only [cost] and the title matter to the celebration; the
/// rest are the schema's non-null columns.
RewardItem rewardItem({required int cost, int index = 0}) => RewardItem(
      rewardId: 'r$index',
      gymId: 'g1',
      title: 'Reward $index',
      pointCost: cost,
      imageUrl: 'https://cdn.test/reward$index.png',
      priceLabel: 'Free',
      isActive: true,
      createdAt: '2026-01-01T00:00:00Z',
    );

/// Decide the app-wide gate on [costs]. The caller must have a selected member
/// (the gate reads its gym / member ids) and must
/// `CelebrationRewardsGate.instance.reset()` in its teardown — the gate is a
/// process-wide singleton, so a leaked catalog changes the next test's flow.
Future<void> primeRewardsGate(List<int> costs) =>
    CelebrationRewardsGate.instance.prime(
      repository: FakeRewardsCatalog(costs),
    );
