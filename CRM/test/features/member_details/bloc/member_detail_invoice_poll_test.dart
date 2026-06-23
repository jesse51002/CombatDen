import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:crm/features/member_details/bloc/invoice_poller.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/member_memberships_mark_paid_cash_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_response.dart';
import 'package:crm/features/member_details/data/models/members_management_response.dart';
import 'package:crm/features/member_details/data/models/personal_info.dart';
import 'package:crm/features/member_details/data/models/retention.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockMemberRepository extends Mock implements MemberRepository {}

class MockMembersManagementResponse extends Mock
    implements MembersManagementResponse {}

/// A spy poller: records that the bloc asked to (re)start polling and
/// captures the tick callback, but schedules NO real timers. The
/// schedule itself is proven in `invoice_poller_test.dart`; here we
/// only verify the bloc starts the poll on the right actions and that a
/// tick re-reads the billing surfaces.
class FakeInvoicePoller extends InvoicePoller {
  int startCount = 0;
  void Function()? lastOnTick;

  @override
  void start(void Function() onTick) {
    startCount++;
    lastOnTick = onTick;
  }

  @override
  void cancel() {}
}

void main() {
  const memberId = 'member-1';
  const gymId = 'gym-1';

  MemberDetailResponse buildMember({String firstName = 'Kid'}) =>
      MemberDetailResponse(
        memberId: memberId,
        gymId: gymId,
        firstName: firstName,
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
  late FakeInvoicePoller poller;

  setUpAll(() {
    registerFallbackValue(
      const MemberMembershipsMarkPaidCashRequest(
        itemId: '',
        memberId: '',
        idempotencyKey: '',
      ),
    );
    registerFallbackValue(
      const MemberMembershipsStartRequest(
        payerMemberId: '',
        gymId: '',
        idempotencyKey: '',
        memberships: [],
      ),
    );
  });

  setUp(() {
    repo = MockMemberRepository();
    poller = FakeInvoicePoller();
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
    when(() => repo.markMembershipPaidCash(any()))
        .thenAnswer((_) async {});
    when(
      () => repo.refundCharge(
        memberId: any(named: 'memberId'),
        chargeId: any(named: 'chargeId'),
        idempotencyKey: any(named: 'idempotencyKey'),
        amount: any(named: 'amount'),
      ),
    ).thenAnswer((_) async {});
    when(() => repo.startMemberships(any())).thenAnswer(
      (_) async => const MemberMembershipsStartResponse(
        chargeCount: 1,
        multipleCharges: false,
      ),
    );
    when(() => repo.unlinkMemberPayment(any()))
        .thenAnswer((_) async => MockMembersManagementResponse());
  });

  MemberDetailBloc build() =>
      MemberDetailBloc(repository: repo, poller: poller);

  group('triggers start the invoice poll', () {
    blocTest<MemberDetailBloc, MemberDetailState>(
      'charge card success starts polling',
      build: build,
      seed: seedState,
      act: (bloc) => bloc.add(
        const ChargeCardRequested(
          amount: 1000,
          description: 'Tee',
          paidByMemberId: memberId,
        ),
      ),
      verify: (_) => expect(poller.startCount, 1),
    );

    blocTest<MemberDetailBloc, MemberDetailState>(
      'start membership success starts polling',
      build: build,
      seed: seedState,
      act: (bloc) => bloc.add(
        const StartMembershipsRequested(
          MemberMembershipsStartRequest(
            payerMemberId: memberId,
            gymId: gymId,
            idempotencyKey: 'k',
            memberships: [],
          ),
        ),
      ),
      verify: (_) => expect(poller.startCount, 1),
    );

    blocTest<MemberDetailBloc, MemberDetailState>(
      'refund success starts polling',
      build: build,
      seed: seedState,
      act: (bloc) => bloc.add(
        const RefundChargeRequested(chargeId: 'ch_1', amount: 500),
      ),
      verify: (_) => expect(poller.startCount, 1),
    );

    blocTest<MemberDetailBloc, MemberDetailState>(
      'mark paid cash success starts polling',
      build: build,
      seed: seedState,
      act: (bloc) => bloc.add(
        const MarkPaidCashRequested(itemId: 'it_1', memberId: memberId),
      ),
      verify: (_) => expect(poller.startCount, 1),
    );
  });

  blocTest<MemberDetailBloc, MemberDetailState>(
    'a non-charge mutation (unlink payment) does NOT start polling',
    build: build,
    seed: seedState,
    act: (bloc) => bloc.add(const UnlinkPaymentRequested()),
    verify: (_) => expect(poller.startCount, 0),
  );

  blocTest<MemberDetailBloc, MemberDetailState>(
    'a poll tick re-fetches member detail and bumps refreshToken',
    build: build,
    seed: seedState,
    act: (bloc) => bloc.add(const InvoicePollRequested()),
    expect: () => [
      isA<MemberDetailLoaded>()
          .having((s) => s.refreshToken, 'refreshToken', 1),
    ],
    verify: (_) {
      verify(() => repo.getMemberDetail(any())).called(1);
    },
  );

  blocTest<MemberDetailBloc, MemberDetailState>(
    'the poll tick still bumps refreshToken when the re-fetch fails '
    '(so the self-fetching sections retry)',
    build: () {
      when(() => repo.getMemberDetail(any()))
          .thenThrow(Exception('billing unreachable'));
      return build();
    },
    seed: seedState,
    act: (bloc) => bloc.add(const InvoicePollRequested()),
    expect: () => [
      isA<MemberDetailLoaded>()
          .having((s) => s.refreshToken, 'refreshToken', 1),
    ],
  );

  // Bloc processes events concurrently, so two ticks can overlap. A
  // slower (older) tick's re-fetch must never overwrite a newer one's.
  blocTest<MemberDetailBloc, MemberDetailState>(
    'a slow earlier tick does NOT overwrite a newer tick (newest wins)',
    build: () {
      final gate = Completer<void>();
      var calls = 0;
      when(() => repo.getMemberDetail(any())).thenAnswer((_) async {
        calls++;
        if (calls == 1) {
          // The first (older) tick is held until the second has landed.
          await gate.future;
          return buildMember(firstName: 'Stale');
        }
        return buildMember(firstName: 'Fresh');
      });
      // Release the first tick only after the second has emitted.
      Future<void>.delayed(const Duration(milliseconds: 20))
          .then((_) => gate.complete());
      return build();
    },
    seed: seedState,
    act: (bloc) async {
      bloc.add(const InvoicePollRequested()); // tick 1 — held
      await Future<void>.delayed(Duration.zero);
      bloc.add(const InvoicePollRequested()); // tick 2 — resolves first
      await Future<void>.delayed(const Duration(milliseconds: 60));
    },
    verify: (bloc) {
      final st = bloc.state as MemberDetailLoaded;
      // Only tick 2 emitted; the stale tick 1 was dropped.
      expect(st.member.firstName, 'Fresh');
      expect(st.refreshToken, 1);
    },
  );
}
