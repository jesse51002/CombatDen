import 'package:bloc_test/bloc_test.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/data/models/cancel_outcome.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/personal_info.dart';
import 'package:crm/features/member_details/data/models/retention.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/rewards/data/repositories/rewards_repository.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockMemberRepository extends Mock implements MemberRepository {}

class MockScheduleRepository extends Mock implements ScheduleRepository {}
class MockRewardsRepository extends Mock implements RewardsRepository {}

/// RemoveAuthorizationRequested must thread the EXACT (payee, payer) pair to
/// the repository — the backend cancel is pair-scoped, so a swapped or wrong
/// id would cancel the wrong member's memberships. This guards the bloc's
/// id threading (the section decides which is payee vs payer), and that the
/// cascading-cancel outcome lands on the state so the unlink completion screen
/// can render it (Feature B).
void main() {
  const viewedId = 'viewed-1';
  const otherId = 'other-1';
  const gymId = 'gym-1';

  MemberDetailResponse buildMember() => const MemberDetailResponse(
        memberId: viewedId,
        gymId: gymId,
        firstName: 'Pat',
        lastName: 'Lee',
        membershipOverview: '1 membership',
        totalMonthlyRecurringPrice: 5000,
        totalMembershipCount: 1,
        personalInfo: PersonalInfo(),
        retention: Retention(
          classStreakWeeks: 0,
          pointsBalance: 0,
          videosWatched: 0,
        ),
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
    when(() => repo.removeAuthorization(any(), any(), any()))
        .thenAnswer(
      (_) async => const CancelOutcome(
        succeededItemIds: ['item-1'],
        failedItemIds: [],
      ),
    );
  });

  blocTest<MemberDetailBloc, MemberDetailState>(
    'remove_authorization passes the exact (payee, payer) pair through',
    build: () => MemberDetailBloc(repository: repo, scheduleRepository: scheduleRepo,
        rewardsRepository: rewardsRepo),
    seed: () => MemberDetailLoaded(
      member: buildMember(),
      allMembers: const [],
      filteredMembers: const [],
    ),
    act: (bloc) => bloc.add(
      const RemoveAuthorizationRequested(
        memberId: viewedId,
        payerMemberId: otherId,
      ),
    ),
    verify: (_) {
      verify(() => repo.removeAuthorization(viewedId, otherId, any()))
          .called(1);
    },
  );

  blocTest<MemberDetailBloc, MemberDetailState>(
    'remove_authorization refetches member detail after the mutation',
    build: () => MemberDetailBloc(repository: repo, scheduleRepository: scheduleRepo,
        rewardsRepository: rewardsRepo),
    seed: () => MemberDetailLoaded(
      member: buildMember(),
      allMembers: const [],
      filteredMembers: const [],
    ),
    act: (bloc) => bloc.add(
      const RemoveAuthorizationRequested(
        memberId: otherId,
        payerMemberId: viewedId,
      ),
    ),
    verify: (_) {
      verify(() => repo.removeAuthorization(otherId, viewedId, any()))
          .called(1);
      verify(() => repo.getMemberDetail(any())).called(1);
    },
  );

  blocTest<MemberDetailBloc, MemberDetailState>(
    'remove_authorization surfaces the cancel outcome + in-flight flag '
    '(Feature B completion screen)',
    build: () => MemberDetailBloc(repository: repo, scheduleRepository: scheduleRepo,
        rewardsRepository: rewardsRepo),
    seed: () => MemberDetailLoaded(
      member: buildMember(),
      allMembers: const [],
      filteredMembers: const [],
    ),
    act: (bloc) => bloc.add(
      const RemoveAuthorizationRequested(
        memberId: viewedId,
        payerMemberId: otherId,
      ),
    ),
    expect: () => [
      // In-flight: the dialog shows its spinner.
      isA<MemberDetailLoaded>()
          .having((s) => s.isRemovingAuthorization, 'removing', true)
          .having((s) => s.removeAuthorizationOutcome, 'outcome', isNull),
      // Settled: the outcome lands so the completion screen renders.
      isA<MemberDetailLoaded>()
          .having((s) => s.isRemovingAuthorization, 'removing', false)
          .having(
            (s) => s.removeAuthorizationOutcome?.succeededItemIds,
            'succeeded',
            ['item-1'],
          ),
    ],
  );

  blocTest<MemberDetailBloc, MemberDetailState>(
    'remove_authorization hard failure surfaces actionError, no outcome',
    build: () {
      when(() => repo.removeAuthorization(any(), any(), any()))
          .thenThrow(Exception('stripe down'));
      return MemberDetailBloc(repository: repo, scheduleRepository: scheduleRepo,
        rewardsRepository: rewardsRepo);
    },
    seed: () => MemberDetailLoaded(
      member: buildMember(),
      allMembers: const [],
      filteredMembers: const [],
    ),
    act: (bloc) => bloc.add(
      const RemoveAuthorizationRequested(
        memberId: viewedId,
        payerMemberId: otherId,
      ),
    ),
    expect: () => [
      isA<MemberDetailLoaded>()
          .having((s) => s.isRemovingAuthorization, 'removing', true),
      isA<MemberDetailLoaded>()
          .having((s) => s.isRemovingAuthorization, 'removing', false)
          .having((s) => s.removeAuthorizationOutcome, 'outcome', isNull)
          .having((s) => s.actionError, 'error', isNotNull),
    ],
  );
}
