import 'package:bloc_test/bloc_test.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/personal_info.dart';
import 'package:crm/features/member_details/data/models/retention.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockMemberRepository extends Mock implements MemberRepository {}

/// charge_card is payer-aware: the dialog picks WHO pays (the member or their
/// linked parent), and that `paidByMemberId` must reach the repository
/// **distinct from** the beneficiary `memberId`. This guards the bloc's
/// threading of the chosen payer.
void main() {
  const childId = 'child-1';
  const parentId = 'parent-1';
  const gymId = 'gym-1';

  MemberDetailResponse buildMember() => const MemberDetailResponse(
        memberId: childId,
        gymId: gymId,
        firstName: 'Kid',
        lastName: 'Smith',
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

  setUp(() {
    repo = MockMemberRepository();
    when(() => repo.getMemberDetail(any()))
        .thenAnswer((_) async => buildMember());
    when(
      () => repo.chargeCard(
        memberId: any(named: 'memberId'),
        paidByMemberId: any(named: 'paidByMemberId'),
        gymId: any(named: 'gymId'),
        amount: any(named: 'amount'),
        reason: any(named: 'reason'),
        idempotencyKey: any(named: 'idempotencyKey'),
        paidCash: any(named: 'paidCash'),
      ),
    ).thenAnswer((_) async {});
  });

  blocTest<MemberDetailBloc, MemberDetailState>(
    'charge_card bills the chosen payer (parent), not the beneficiary member',
    build: () => MemberDetailBloc(repository: repo),
    seed: () => MemberDetailLoaded(
      member: buildMember(),
      allMembers: const [],
      filteredMembers: const [],
    ),
    act: (bloc) => bloc.add(
      const ChargeCardRequested(
        amount: 1000,
        description: 'Pro-shop tee',
        paidByMemberId: parentId,
      ),
    ),
    verify: (_) {
      verify(
        () => repo.chargeCard(
          memberId: childId,
          paidByMemberId: parentId,
          gymId: gymId,
          amount: 1000,
          reason: 'Pro-shop tee',
          idempotencyKey: any(named: 'idempotencyKey'),
          paidCash: any(named: 'paidCash'),
        ),
      ).called(1);
    },
  );

  blocTest<MemberDetailBloc, MemberDetailState>(
    'charge_card self-pay sends the member as their own payer',
    build: () => MemberDetailBloc(repository: repo),
    seed: () => MemberDetailLoaded(
      member: buildMember(),
      allMembers: const [],
      filteredMembers: const [],
    ),
    act: (bloc) => bloc.add(
      const ChargeCardRequested(
        amount: 2500,
        description: 'Private session',
        paidByMemberId: childId,
      ),
    ),
    verify: (_) {
      verify(
        () => repo.chargeCard(
          memberId: childId,
          paidByMemberId: childId,
          gymId: gymId,
          amount: 2500,
          reason: 'Private session',
          idempotencyKey: any(named: 'idempotencyKey'),
          paidCash: any(named: 'paidCash'),
        ),
      ).called(1);
    },
  );
}
