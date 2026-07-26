import 'package:bloc_test/bloc_test.dart';
import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/features/member_details/bloc/invoice_poller.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/member_memberships_retry_card_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_retry_card_response.dart';
import 'package:crm/features/member_details/data/models/member_memberships_retry_card_status.dart';
import 'package:crm/features/member_details/data/models/personal_info.dart';
import 'package:crm/features/member_details/data/models/retention.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/memberships/data/repositories/ranks_repository.dart';
import 'package:crm/features/rewards/data/repositories/rewards_repository.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:crm/features/emails/data/repositories/emails_repository.dart';

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
        emailsRepository: _stubEmailsRepository,
        
        repository: repo,
        ranksRepository: MockRanksRepository(),
        scheduleRepository: scheduleRepo,
        rewardsRepository: rewardsRepo,
        poller: FakeInvoicePoller(),
      );

  MemberMembershipsRetryCardResponse outcome(
    MemberMembershipsRetryCardStatus status, {
    String? declineReason,
  }) =>
      MemberMembershipsRetryCardResponse(
        itemId: 'it_1',
        memberId: memberId,
        status: status,
        declineReason: declineReason,
      );

  group('retry-payment channel', () {
    blocTest<MemberDetailBloc, MemberDetailState>(
      'a paid outcome bumps retryPaymentSuccess + refreshToken (own channel)',
      setUp: () => when(() => repo.retryMembershipCard(any())).thenAnswer(
        (_) async => outcome(MemberMembershipsRetryCardStatus.paid),
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
        // The best-effort member re-fetch returns an equal member, so its
        // copyWith is deduped — the success state is the last emission.
        isA<MemberDetailLoaded>()
            .having((s) => s.isRetryingPayment, 'isRetryingPayment', false)
            .having((s) => s.retryPaymentSuccess, 'retryPaymentSuccess', 1)
            .having((s) => s.refreshToken, 'refreshToken', 1)
            .having((s) => s.retryPaymentError, 'retryPaymentError', isNull),
      ],
    );

    // THE regression guard for the 500 → 207 move: the backend now returns a
    // decline as a 2xx RESULT, so it no longer throws. If the bloc ever
    // treats a returned outcome as success again, retryPaymentSuccess bumps
    // and retryPaymentError stays null — and this test fails. The dialog reads
    // exactly these two fields, so a green-but-declined retry would tell staff
    // an unpaid invoice was collected.
    blocTest<MemberDetailBloc, MemberDetailState>(
      'a DECLINED 2xx outcome is an error, never a success',
      setUp: () => when(() => repo.retryMembershipCard(any())).thenAnswer(
        (_) async => outcome(
          MemberMembershipsRetryCardStatus.declined,
          declineReason: 'Your card was declined.',
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
            .having((s) => s.refreshToken, 'refreshToken', 0)
            .having((s) => s.actionError, 'actionError', isNull),
      ],
      verify: (_) {
        // A decline must not be followed by the success path's re-fetch or
        // invoice poll — nothing was collected.
        verifyNever(() => repo.getMemberDetail(any()));
      },
    );

    blocTest<MemberDetailBloc, MemberDetailState>(
      'an unknown status fails closed with the unconfirmed message',
      setUp: () => when(() => repo.retryMembershipCard(any())).thenAnswer(
        (_) async => outcome(MemberMembershipsRetryCardStatus.unknown),
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
              contains('not confirmed'),
            )
            .having((s) => s.retryPaymentSuccess, 'retryPaymentSuccess', 0),
      ],
    );

    blocTest<MemberDetailBloc, MemberDetailState>(
      'a system failure (500) still surfaces its detail on retryPaymentError, '
      'never on actionError',
      setUp: () => when(() => repo.retryMembershipCard(any())).thenThrow(
        const ServerException(
          'Internal Server Error',
          statusCode: 500,
          detail: 'Failed to retry the card on membership',
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
              'Failed to retry the card on membership',
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


/// Stub for the emails repository the bloc now takes. No test here exercises
/// the manual app-invite send, so it is never stubbed — only supplied.
class _StubEmailsRepository extends Mock implements EmailsRepository {}

final _stubEmailsRepository = _StubEmailsRepository();
