import 'package:bloc_test/bloc_test.dart';
import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/data/models/cancel_outcome.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/personal_info.dart';
import 'package:crm/features/member_details/data/models/retention.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/memberships/data/repositories/ranks_repository.dart';
import 'package:crm/features/rewards/data/repositories/rewards_repository.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockMemberRepository extends Mock implements MemberRepository {}

class MockScheduleRepository extends Mock implements ScheduleRepository {}
class MockRewardsRepository extends Mock implements RewardsRepository {}

class MockRanksRepository extends Mock implements RanksRepository {}

void main() {
  const memberId = 'member-1';
  const gymId = 'gym-1';
  const itemId1 = 'item-a';
  const itemId2 = 'item-b';

  MemberDetailResponse buildMember() => const MemberDetailResponse(
        memberId: memberId,
        gymId: gymId,
        firstName: 'Alex',
        lastName: 'Kim',
        membershipOverview: '2 memberships',
        totalMonthlyRecurringPrice: 10000,
        totalMembershipCount: 2,
        personalInfo: PersonalInfo(),
        retention: Retention(
          classStreakWeeks: 0,
          pointsBalance: 0,
          videosWatched: 0,
        ),
      );

  MemberDetailLoaded buildSeed() => MemberDetailLoaded(
        member: buildMember(),
        allMembers: const [],
        filteredMembers: const [],
      );

  late MockMemberRepository repo;
  late MockScheduleRepository scheduleRepo;
  late MockRewardsRepository rewardsRepo;

  setUp(() {
    repo = MockMemberRepository();
    scheduleRepo = MockScheduleRepository();
    rewardsRepo = MockRewardsRepository();
    when(() => repo.getMemberDetail(any()))
        .thenAnswer((_) async => buildMember());
    registerFallbackValue(
      const CancelOutcome(
        succeededItemIds: [],
        failedItemIds: [],
      ),
    );
  });

  // ── All succeeded ──────────────────────────────────────────────────────────

  blocTest<MemberDetailBloc, MemberDetailState>(
    'all-succeeded: emits isCancellingMemberships=true then '
    'cancelOutcome with all item_ids succeeded',
    build: () {
      when(
        () => repo.cancelMemberships(
          itemIds: any(named: 'itemIds'),
          memberId: any(named: 'memberId'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenAnswer(
        (_) async => const CancelOutcome(
          succeededItemIds: [itemId1, itemId2],
          failedItemIds: [],
        ),
      );
      return MemberDetailBloc(repository: repo, ranksRepository: MockRanksRepository(), scheduleRepository: scheduleRepo, rewardsRepository: rewardsRepo);
    },
    seed: buildSeed,
    act: (bloc) => bloc.add(
      const CancelMembershipRequested(
        itemIds: [itemId1, itemId2],
        memberId: memberId,
      ),
    ),
    expect: () => [
      isA<MemberDetailLoaded>().having(
        (s) => s.isCancellingMemberships,
        'isCancellingMemberships',
        true,
      ),
      isA<MemberDetailLoaded>()
          .having(
            (s) => s.isCancellingMemberships,
            'isCancellingMemberships',
            false,
          )
          .having(
            (s) => s.cancelOutcome?.succeededItemIds,
            'succeededItemIds',
            containsAll([itemId1, itemId2]),
          )
          .having(
            (s) => s.cancelOutcome?.failedItemIds,
            'failedItemIds',
            isEmpty,
          ),
    ],
  );

  // ── Partial (some succeeded, some failed) ─────────────────────────────────
  // The repository parses the structured 502 detail
  // ({succeeded_item_ids, failed_item_ids}) into this split (covered in
  // data/cancel_memberships_repository_test.dart); here we assert the bloc
  // relays the real split through to `cancelOutcome` unchanged.

  blocTest<MemberDetailBloc, MemberDetailState>(
    'partial: emits isCancellingMemberships=true then '
    'cancelOutcome with one succeeded and one failed',
    build: () {
      when(
        () => repo.cancelMemberships(
          itemIds: any(named: 'itemIds'),
          memberId: any(named: 'memberId'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenAnswer(
        (_) async => const CancelOutcome(
          succeededItemIds: [itemId1],
          failedItemIds: [itemId2],
        ),
      );
      return MemberDetailBloc(repository: repo, ranksRepository: MockRanksRepository(), scheduleRepository: scheduleRepo, rewardsRepository: rewardsRepo);
    },
    seed: buildSeed,
    act: (bloc) => bloc.add(
      const CancelMembershipRequested(
        itemIds: [itemId1, itemId2],
        memberId: memberId,
      ),
    ),
    expect: () => [
      isA<MemberDetailLoaded>().having(
        (s) => s.isCancellingMemberships,
        'isCancellingMemberships',
        true,
      ),
      isA<MemberDetailLoaded>()
          .having(
            (s) => s.isCancellingMemberships,
            'isCancellingMemberships',
            false,
          )
          .having(
            (s) => s.cancelOutcome?.succeededItemIds,
            'succeededItemIds',
            [itemId1],
          )
          .having(
            (s) => s.cancelOutcome?.failedItemIds,
            'failedItemIds',
            [itemId2],
          ),
    ],
  );

  // ── All failed ────────────────────────────────────────────────────────────

  blocTest<MemberDetailBloc, MemberDetailState>(
    'all-failed: repository returns all-failed outcome; '
    'bloc emits cancelOutcome with all item_ids in failedItemIds',
    build: () {
      when(
        () => repo.cancelMemberships(
          itemIds: any(named: 'itemIds'),
          memberId: any(named: 'memberId'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenAnswer(
        (_) async => const CancelOutcome(
          succeededItemIds: [],
          failedItemIds: [itemId1, itemId2],
        ),
      );
      return MemberDetailBloc(repository: repo, ranksRepository: MockRanksRepository(), scheduleRepository: scheduleRepo, rewardsRepository: rewardsRepo);
    },
    seed: buildSeed,
    act: (bloc) => bloc.add(
      const CancelMembershipRequested(
        itemIds: [itemId1, itemId2],
        memberId: memberId,
      ),
    ),
    expect: () => [
      isA<MemberDetailLoaded>().having(
        (s) => s.isCancellingMemberships,
        'isCancellingMemberships',
        true,
      ),
      isA<MemberDetailLoaded>()
          .having(
            (s) => s.isCancellingMemberships,
            'isCancellingMemberships',
            false,
          )
          .having(
            (s) => s.cancelOutcome?.succeededItemIds,
            'succeededItemIds',
            isEmpty,
          )
          .having(
            (s) => s.cancelOutcome?.failedItemIds,
            'failedItemIds',
            containsAll([itemId1, itemId2]),
          ),
    ],
  );

  // ── MembershipInTaskException propagates as all-failed ────────────────────

  blocTest<MemberDetailBloc, MemberDetailState>(
    'MembershipInTaskException: throws through the bloc; '
    'cancelOutcome carries all item_ids as failed',
    build: () {
      when(
        () => repo.cancelMemberships(
          itemIds: any(named: 'itemIds'),
          memberId: any(named: 'memberId'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenThrow(
        const MembershipInTaskException(
          'Membership is inside an unfinished task.',
        ),
      );
      return MemberDetailBloc(repository: repo, ranksRepository: MockRanksRepository(), scheduleRepository: scheduleRepo, rewardsRepository: rewardsRepo);
    },
    seed: buildSeed,
    act: (bloc) => bloc.add(
      const CancelMembershipRequested(
        itemIds: [itemId1, itemId2],
        memberId: memberId,
      ),
    ),
    expect: () => [
      isA<MemberDetailLoaded>().having(
        (s) => s.isCancellingMemberships,
        'isCancellingMemberships',
        true,
      ),
      isA<MemberDetailLoaded>()
          .having(
            (s) => s.isCancellingMemberships,
            'isCancellingMemberships',
            false,
          )
          .having(
            (s) => s.cancelOutcome?.failedItemIds,
            'failedItemIds',
            containsAll([itemId1, itemId2]),
          ),
    ],
  );

  // ── Member detail is always refreshed ────────────────────────────────────

  blocTest<MemberDetailBloc, MemberDetailState>(
    'getMemberDetail is called after cancel regardless of outcome',
    build: () {
      when(
        () => repo.cancelMemberships(
          itemIds: any(named: 'itemIds'),
          memberId: any(named: 'memberId'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenAnswer(
        (_) async => const CancelOutcome(
          succeededItemIds: [itemId1],
          failedItemIds: [],
        ),
      );
      return MemberDetailBloc(repository: repo, ranksRepository: MockRanksRepository(), scheduleRepository: scheduleRepo, rewardsRepository: rewardsRepo);
    },
    seed: buildSeed,
    act: (bloc) => bloc.add(
      const CancelMembershipRequested(
        itemIds: [itemId1],
        memberId: memberId,
      ),
    ),
    verify: (_) {
      verify(() => repo.getMemberDetail(memberId)).called(1);
    },
  );

  // ── CancelMembershipOutcomeCleared ────────────────────────────────────────

  blocTest<MemberDetailBloc, MemberDetailState>(
    'CancelMembershipOutcomeCleared wipes cancelOutcome from state',
    build: () => MemberDetailBloc(repository: repo, ranksRepository: MockRanksRepository(), scheduleRepository: scheduleRepo, rewardsRepository: rewardsRepo),
    seed: () => MemberDetailLoaded(
      member: buildMember(),
      allMembers: const [],
      filteredMembers: const [],
      cancelOutcome: const CancelOutcome(
        succeededItemIds: [itemId1],
        failedItemIds: [],
      ),
    ),
    act: (bloc) =>
        bloc.add(const CancelMembershipOutcomeCleared()),
    expect: () => [
      isA<MemberDetailLoaded>().having(
        (s) => s.cancelOutcome,
        'cancelOutcome',
        isNull,
      ),
    ],
  );
}
