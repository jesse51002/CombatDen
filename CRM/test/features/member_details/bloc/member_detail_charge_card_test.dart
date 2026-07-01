import 'package:bloc_test/bloc_test.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/personal_info.dart';
import 'package:crm/features/member_details/data/models/retention.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockMemberRepository extends Mock implements MemberRepository {}

class MockScheduleRepository extends Mock implements ScheduleRepository {}

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
  late MockScheduleRepository scheduleRepo;

  setUp(() {
    repo = MockMemberRepository();
    scheduleRepo = MockScheduleRepository();
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
        paymentMethodId: any(named: 'paymentMethodId'),
      ),
    ).thenAnswer((_) async {});
  });

  blocTest<MemberDetailBloc, MemberDetailState>(
    'charge_card bills the chosen payer (parent), not the beneficiary member',
    build: () => MemberDetailBloc(repository: repo, scheduleRepository: scheduleRepo),
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
    build: () => MemberDetailBloc(repository: repo, scheduleRepository: scheduleRepo),
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

  blocTest<MemberDetailBloc, MemberDetailState>(
    'charge_card threads a one-off payment_method_id to the repository',
    build: () => MemberDetailBloc(repository: repo, scheduleRepository: scheduleRepo),
    seed: () => MemberDetailLoaded(
      member: buildMember(),
      allMembers: const [],
      filteredMembers: const [],
    ),
    act: (bloc) => bloc.add(
      const ChargeCardRequested(
        amount: 3300,
        description: 'One-off card',
        paidByMemberId: childId,
        paymentMethodId: 'pm_123',
      ),
    ),
    verify: (_) {
      verify(
        () => repo.chargeCard(
          memberId: childId,
          paidByMemberId: childId,
          gymId: gymId,
          amount: 3300,
          reason: 'One-off card',
          idempotencyKey: any(named: 'idempotencyKey'),
          paidCash: any(named: 'paidCash'),
          paymentMethodId: 'pm_123',
        ),
      ).called(1);
    },
  );

  blocTest<MemberDetailBloc, MemberDetailState>(
    'charge_card out-of-band threads paid_cash to the repository',
    build: () => MemberDetailBloc(repository: repo, scheduleRepository: scheduleRepo),
    seed: () => MemberDetailLoaded(
      member: buildMember(),
      allMembers: const [],
      filteredMembers: const [],
    ),
    act: (bloc) => bloc.add(
      const ChargeCardRequested(
        amount: 2000,
        description: 'Cash drop-in',
        paidByMemberId: childId,
        paidCash: true,
      ),
    ),
    verify: (_) {
      verify(
        () => repo.chargeCard(
          memberId: childId,
          paidByMemberId: childId,
          gymId: gymId,
          amount: 2000,
          reason: 'Cash drop-in',
          idempotencyKey: any(named: 'idempotencyKey'),
          paidCash: true,
          paymentMethodId: any(named: 'paymentMethodId'),
        ),
      ).called(1);
    },
  );

  // The charge runs on its OWN state channel (isChargingCard /
  // chargeCardSuccess / chargeCardError) so the dialog owns the
  // outcome — it never touches isMutating / actionError (which would
  // fire the screen-level overlay + error dialog).
  blocTest<MemberDetailBloc, MemberDetailState>(
    'charge_card success bumps chargeCardSuccess, not isMutating/actionError',
    build: () => MemberDetailBloc(repository: repo, scheduleRepository: scheduleRepo),
    seed: () => MemberDetailLoaded(
      member: buildMember(),
      allMembers: const [],
      filteredMembers: const [],
    ),
    act: (bloc) => bloc.add(
      const ChargeCardRequested(
        amount: 1000,
        description: 'Tee',
        paidByMemberId: childId,
      ),
    ),
    expect: () => [
      isA<MemberDetailLoaded>()
          .having((s) => s.isChargingCard, 'isChargingCard', true)
          .having((s) => s.isMutating, 'isMutating', false)
          .having((s) => s.actionError, 'actionError', null),
      isA<MemberDetailLoaded>()
          .having((s) => s.isChargingCard, 'isChargingCard', false)
          .having((s) => s.chargeCardSuccess, 'chargeCardSuccess', 1)
          .having((s) => s.refreshToken, 'refreshToken', 1)
          .having((s) => s.isMutating, 'isMutating', false)
          .having((s) => s.actionError, 'actionError', null),
    ],
  );

  blocTest<MemberDetailBloc, MemberDetailState>(
    'charge_card failure lands on chargeCardError, not actionError',
    build: () {
      when(
        () => repo.chargeCard(
          memberId: any(named: 'memberId'),
          paidByMemberId: any(named: 'paidByMemberId'),
          gymId: any(named: 'gymId'),
          amount: any(named: 'amount'),
          reason: any(named: 'reason'),
          idempotencyKey: any(named: 'idempotencyKey'),
          paidCash: any(named: 'paidCash'),
          paymentMethodId: any(named: 'paymentMethodId'),
        ),
      ).thenThrow(Exception('card declined'));
      return MemberDetailBloc(repository: repo, scheduleRepository: scheduleRepo);
    },
    seed: () => MemberDetailLoaded(
      member: buildMember(),
      allMembers: const [],
      filteredMembers: const [],
    ),
    act: (bloc) => bloc.add(
      const ChargeCardRequested(
        amount: 1000,
        description: 'Tee',
        paidByMemberId: childId,
      ),
    ),
    expect: () => [
      isA<MemberDetailLoaded>()
          .having((s) => s.isChargingCard, 'isChargingCard', true),
      isA<MemberDetailLoaded>()
          .having((s) => s.isChargingCard, 'isChargingCard', false)
          .having((s) => s.chargeCardError, 'chargeCardError', isNotNull)
          .having((s) => s.actionError, 'actionError', null),
    ],
  );

  // The charge (money) succeeded; only the follow-up member-detail refresh
  // failed. That must NOT surface as a charge error — otherwise staff see a
  // "failed" charge and re-charge a card that was already billed.
  blocTest<MemberDetailBloc, MemberDetailState>(
    'charge_card success stands when the post-charge refresh throws '
    '(no false chargeCardError)',
    build: () {
      // chargeCard succeeds (the setUp stub); the refresh throws.
      when(() => repo.getMemberDetail(any()))
          .thenThrow(Exception('member refresh unreachable'));
      return MemberDetailBloc(repository: repo, scheduleRepository: scheduleRepo);
    },
    seed: () => MemberDetailLoaded(
      member: buildMember(),
      allMembers: const [],
      filteredMembers: const [],
    ),
    act: (bloc) => bloc.add(
      const ChargeCardRequested(
        amount: 1000,
        description: 'Tee',
        paidByMemberId: childId,
      ),
    ),
    expect: () => [
      isA<MemberDetailLoaded>()
          .having((s) => s.isChargingCard, 'isChargingCard', true),
      isA<MemberDetailLoaded>()
          .having((s) => s.isChargingCard, 'isChargingCard', false)
          .having((s) => s.chargeCardSuccess, 'chargeCardSuccess', 1)
          .having((s) => s.chargeCardError, 'chargeCardError', null),
    ],
    verify: (_) {
      verify(() => repo.getMemberDetail(any())).called(1);
    },
  );
}
