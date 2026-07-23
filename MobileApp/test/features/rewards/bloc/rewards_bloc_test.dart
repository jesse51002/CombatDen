import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_app/core/errors/exceptions.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/rewards/bloc/rewards_bloc.dart';
import 'package:mobile_app/features/rewards/bloc/rewards_event.dart';
import 'package:mobile_app/features/rewards/bloc/rewards_state.dart';
import 'package:mobile_app/features/rewards/data/models/redeem_result.dart';
import 'package:mobile_app/features/rewards/data/models/redemption_record.dart';
import 'package:mobile_app/features/rewards/data/models/reward_item.dart';
import 'package:mobile_app/features/rewards/data/repositories/member_rewards_repository.dart';

class _MockRewardsRepo extends Mock implements MemberRewardsRepository {}

RewardItem _reward({String id = 'r1', int cost = 500}) => RewardItem(
      rewardId: id,
      gymId: 'g1',
      title: 'Free week',
      pointCost: cost,
      imageUrl: 'https://x/i.png',
      priceLabel: 'Free',
      isActive: true,
      createdAt: '2026-07-23T00:00:00Z',
    );

RedemptionRecord _redemption({String id = 'rd1'}) => RedemptionRecord(
      redemptionId: id,
      rewardId: 'r1',
      title: 'Free week',
      imageUrl: 'https://x/i.png',
      priceLabel: 'Free',
      pointCost: 500,
      requestedAt: '2026-07-23T00:00:00Z',
      status: RedemptionStatus.pending,
    );

RedeemResult _result() => const RedeemResult(
      redemptionId: 'rd1',
      memberId: 'm1',
      rewardId: 'r1',
      gymId: 'g1',
      pointCost: 500,
      requestedAt: '2026-07-23T00:00:00Z',
      status: RedemptionStatus.pending,
      pointsBalanceAfter: 750,
    );

void main() {
  late _MockRewardsRepo repo;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await selectedMember.select(
      memberId: 'm1',
      gymId: 'g1',
      gymName: 'Global MMA',
      firstName: 'Jane',
      lastName: 'Doe',
    );
    repo = _MockRewardsRepo();
  });

  void stubCatalog(List<RewardItem> catalog) {
    when(() => repo.listCatalog(
          gymId: any(named: 'gymId'),
          memberId: any(named: 'memberId'),
        )).thenAnswer((_) async => catalog);
  }

  void stubRedemptions(List<RedemptionRecord> redemptions) {
    when(() => repo.listRedemptions(
          gymId: any(named: 'gymId'),
          memberId: any(named: 'memberId'),
        )).thenAnswer((_) async => redemptions);
  }

  void stubRedeem(RedeemResult result) {
    when(() => repo.redeem(
          gymId: any(named: 'gymId'),
          memberId: any(named: 'memberId'),
          rewardId: any(named: 'rewardId'),
        )).thenAnswer((_) async => result);
  }

  RewardsBloc build() => RewardsBloc(repository: repo);

  blocTest<RewardsBloc, RewardsState>(
    'load fetches the catalog and the redemption history',
    setUp: () {
      stubCatalog([_reward()]);
      stubRedemptions([_redemption()]);
    },
    build: build,
    act: (b) => b.add(const RewardsLoadRequested()),
    expect: () => [
      isA<RewardsState>()
          .having((s) => s.status, 'status', RewardsStatus.loading),
      isA<RewardsState>()
          .having((s) => s.status, 'status', RewardsStatus.loaded)
          .having((s) => s.catalog.length, 'catalog', 1)
          .having((s) => s.redemptions.length, 'redemptions', 1),
    ],
  );

  blocTest<RewardsBloc, RewardsState>(
    'a redemptions failure degrades gracefully — the catalog still loads',
    setUp: () {
      stubCatalog([_reward()]);
      when(() => repo.listRedemptions(
            gymId: any(named: 'gymId'),
            memberId: any(named: 'memberId'),
          )).thenThrow(const NetworkException('offline'));
    },
    build: build,
    act: (b) => b.add(const RewardsLoadRequested()),
    expect: () => [
      isA<RewardsState>()
          .having((s) => s.status, 'status', RewardsStatus.loading),
      isA<RewardsState>()
          .having((s) => s.status, 'status', RewardsStatus.loaded)
          .having((s) => s.catalog.length, 'catalog', 1)
          .having((s) => s.redemptions, 'redemptions', isEmpty),
    ],
  );

  blocTest<RewardsBloc, RewardsState>(
    'a catalog failure surfaces a retry-able error',
    setUp: () {
      when(() => repo.listCatalog(
            gymId: any(named: 'gymId'),
            memberId: any(named: 'memberId'),
          )).thenThrow(const NetworkException('offline'));
    },
    build: build,
    act: (b) => b.add(const RewardsLoadRequested()),
    expect: () => [
      isA<RewardsState>()
          .having((s) => s.status, 'status', RewardsStatus.loading),
      isA<RewardsState>()
          .having((s) => s.status, 'status', RewardsStatus.error)
          .having((s) => s.errorMessage, 'errorMessage', 'offline'),
    ],
  );

  blocTest<RewardsBloc, RewardsState>(
    'redeem success bumps the token that triggers the profile-refresh hook',
    setUp: () => stubRedeem(_result()),
    build: build,
    seed: () => RewardsState(
      status: RewardsStatus.loaded,
      catalog: [_reward()],
    ),
    act: (b) => b.add(const RewardsRedeemRequested(rewardId: 'r1')),
    expect: () => [
      isA<RewardsState>().having((s) => s.isRedeeming, 'isRedeeming', true),
      isA<RewardsState>()
          .having((s) => s.isRedeeming, 'isRedeeming', false)
          .having((s) => s.redeemSuccessToken, 'token', 1)
          .having((s) => s.redeemError, 'redeemError', isNull),
    ],
  );

  blocTest<RewardsBloc, RewardsState>(
    'a redeem 4xx surfaces the backend detail without a crash or token bump',
    setUp: () {
      when(() => repo.redeem(
            gymId: any(named: 'gymId'),
            memberId: any(named: 'memberId'),
            rewardId: any(named: 'rewardId'),
          )).thenThrow(
        const ServerException(
          'Server error 400',
          statusCode: 400,
          detail: 'Not enough points',
        ),
      );
    },
    build: build,
    seed: () => RewardsState(
      status: RewardsStatus.loaded,
      catalog: [_reward()],
    ),
    act: (b) => b.add(const RewardsRedeemRequested(rewardId: 'r1')),
    expect: () => [
      isA<RewardsState>().having((s) => s.isRedeeming, 'isRedeeming', true),
      isA<RewardsState>()
          .having((s) => s.isRedeeming, 'isRedeeming', false)
          .having((s) => s.redeemError, 'redeemError', 'Not enough points')
          .having((s) => s.redeemSuccessToken, 'token', 0),
    ],
  );
}
