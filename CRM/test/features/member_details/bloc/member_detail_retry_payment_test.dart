import 'package:bloc_test/bloc_test.dart';
import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/features/member_details/bloc/invoice_poller.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/member_memberships_retry_card_request.dart';
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

/// No real timers (a successful retry starts the invoice poll; the
/// schedule itself is proven in `invoice_poller_test.dart`).
class FakeInvoicePoller extends InvoicePoller {
  @override
  void start(void Function() onTick) {}
  @override
  void cancel() {}
}

void main() {
  const memberId = 'member-1';
  const gymId = 'gym-1';

  MemberDetailResponse buildMember() => MemberDetailResponse(
        memberId: memberId,
        gymId: gymId,
        firstName: 'Kid',
        lastName: 'Smith',
        membershipOverview: '1 membership',
        totalMonthlyRecurringPrice: 5000,
        totalMembershipCount: 1,
        personalInfo: const PersonalInfo(),
        retention: const Retention(
          classStreakWeeks: 0,
          pointsBalance: 0,
          videosWatched: 0,
        ),
      );

  MemberDetailLoaded seedState() => MemberDetailLoaded(
        member: buildMember(),
        allMembers: const [],
        filteredMembers: const [],
      );

  late MockMemberRepository repo;
  late MockScheduleRepository scheduleRepo;
  late MockRewardsRepository rewardsRepo;

  setUpAll(() {
    registerFallbackValue(
      const MemberMembershipsRetryCardRequest(
        itemId: '',
        memberId: '',
        idempotencyKey: '',
      ),
    );
  });

  setUp(() {
    repo = MockMemberRepository();
    scheduleRepo = MockScheduleRepository();
    rewardsRepo = MockRewardsRepository();
    when(() => repo.getMemberDetail(any()))
        .thenAnswer((_) async => buildMember());
  });

  MemberDetailBloc build() => MemberDetailBloc(
        repository: repo,
        ranksRepository: MockRanksRepository(),
        scheduleRepository: scheduleRepo,
        rewardsRepository: rewardsRepo,
        poller: FakeInvoicePoller(),
      );

  group('retry-payment channel', () {
    blocTest<MemberDetailBloc, MemberDetailState>(
      'success bumps retryPaymentSuccess + refreshToken (own channel)',
      setUp: () => when(() => repo.retryMembershipCard(any()))
          .thenAnswer((_) async {}),
      build: build,
      seed: seedState,
      act: (bloc) => bloc.add(const RetryCardPaymentRequested(
        itemId: 'it_1',
        memberId: memberId,
      )),
      expect: () => [
        isA<MemberDetailLoaded>()
            .having((s) => s.isRetryingPayment, 'isRetryingPayment', true),
        // The best-effort member re-fetch returns an equal member, so its
        // copyWith is deduped — the success state is the last emission.
        isA<MemberDetailLoaded>()
            .having((s) => s.isRetryingPayment, 'isRetryingPayment', false)
            .having((s) => s.retryPaymentSuccess, 'retryPaymentSuccess', 1)
            .having((s) => s.refreshToken, 'refreshToken', 1)
            .having((s) => s.retryPaymentError, 'retryPaymentError', isNull),
      ],
    );

    blocTest<MemberDetailBloc, MemberDetailState>(
      'a decline surfaces the backend detail on retryPaymentError, '
      'never on actionError',
      setUp: () => when(() => repo.retryMembershipCard(any())).thenThrow(
        const ServerException(
          'Internal Server Error',
          statusCode: 500,
          detail: 'Your card was declined.',
        ),
      ),
      build: build,
      seed: seedState,
      act: (bloc) => bloc.add(const RetryCardPaymentRequested(
        itemId: 'it_1',
        memberId: memberId,
      )),
      expect: () => [
        isA<MemberDetailLoaded>()
            .having((s) => s.isRetryingPayment, 'isRetryingPayment', true),
        isA<MemberDetailLoaded>()
            .having((s) => s.isRetryingPayment, 'isRetryingPayment', false)
            .having(
              (s) => s.retryPaymentError,
              'retryPaymentError',
              'Your card was declined.',
            )
            .having((s) => s.retryPaymentSuccess, 'retryPaymentSuccess', 0)
            .having((s) => s.actionError, 'actionError', isNull),
      ],
    );

    blocTest<MemberDetailBloc, MemberDetailState>(
      'clearing the outcome wipes a prior decline',
      build: build,
      seed: () => seedState().copyWith(
        retryPaymentError: 'Your card was declined.',
      ),
      act: (bloc) =>
          bloc.add(const RetryCardPaymentOutcomeCleared()),
      expect: () => [
        isA<MemberDetailLoaded>()
            .having((s) => s.retryPaymentError, 'retryPaymentError', isNull),
      ],
    );
  });
}
