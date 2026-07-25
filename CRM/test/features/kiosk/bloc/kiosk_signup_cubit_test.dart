import 'package:bloc_test/bloc_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_session_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/member_details/data/models/duplicate_member_match.dart';
import 'package:crm/features/member_details/data/models/members_management_create_request.dart';
import 'package:crm/features/member_details/data/models/members_management_response.dart';
import 'package:crm/features/member_details/data/models/members_management_update_request.dart';
import 'package:crm/features/member_details/data/models/membership_plan_price_response.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/members_list/data/repositories/members_list_repository.dart';
import 'package:crm/features/memberships/data/repositories/memberships_repository.dart';

class _MockMemberRepository extends Mock implements MemberRepository {}

class _MockMembershipsRepository extends Mock
    implements MembershipsRepository {}

class _MockMembersListRepository extends Mock
    implements MembersListRepository {}

class _MockKioskSessionCubit extends Mock implements KioskSessionCubit {}

class _MockManagementResponse extends Mock
    implements MembersManagementResponse {}

/// The kiosk SIGNUP lane's cubit: begins the session flow exactly once, writes
/// the member with ONE create call carrying both detail steps, turns every
/// failure into a terminal front-desk stop, runs its own 5-minute idle guard,
/// and (ruling 11) never fires a second create out of a committed step.
void main() {
  const gymId = 'gym-1';
  final t0 = DateTime.utc(2026, 1, 1, 18);

  late _MockMemberRepository member;
  late _MockMembershipsRepository memberships;
  late _MockMembersListRepository membersList;
  late _MockKioskSessionCubit session;

  setUpAll(() {
    registerFallbackValue(
      const MembersManagementCreateRequest(
        gymId: gymId,
        firstName: 'a',
        lastName: 'b',
      ),
    );
    registerFallbackValue(const MembersManagementUpdateRequest());
  });

  setUp(() {
    member = _MockMemberRepository();
    memberships = _MockMembershipsRepository();
    membersList = _MockMembersListRepository();
    session = _MockKioskSessionCubit();
    when(() => memberships.listPlans(any()))
        .thenAnswer((_) async => <MembershipPlanResponse>[]);
    when(() => member.createMember(any())).thenAnswer((_) async => 'mem-new');
    when(() => member.updateMember(any(), any()))
        .thenAnswer((_) async => _MockManagementResponse());
  });

  KioskSignupCubit build() => KioskSignupCubit(
        memberRepository: member,
        membershipsRepository: memberships,
        membersListRepository: membersList,
        session: session,
        gymId: gymId,
        now: () => t0,
        uuid: () => 'key-1',
      );

  /// Walk the two detail steps to the create call.
  Future<void> fillAndCommit(KioskSignupCubit cubit) async {
    cubit.submitDetails(
      firstName: 'Marcus',
      lastName: 'Bell',
      email: 'marcus.bell@gmail.com',
      phone: '(512) 555-0114',
    );
    await cubit.submitExtraDetails(
      dob: DateTime(1994, 4, 12),
      address: '18 Mill St',
      ecName: 'Dana Bell',
    );
  }

  group('flow-count discipline', () {
    test('beginFlow fires exactly once, in the constructor', () {
      final cubit = build();
      verify(() => session.beginFlow()).called(1);
      cubit.close();
    });

    test('close() balances the flow count on a mid-flow teardown', () async {
      final cubit = build();
      cubit.submitDetails(
        firstName: 'Marcus',
        lastName: 'Bell',
        email: 'marcus.bell@gmail.com',
      );
      await cubit.close();
      // Exactly one endFlow per beginFlow on EVERY exit path — a leak means
      // the kiosk never signs itself out at its T+11h45 lockout.
      verify(() => session.beginFlow()).called(1);
      verify(() => session.endFlow()).called(1);
    });

    test('a stop then a close still releases exactly once (the latch)',
        () async {
      when(() => member.createMember(any()))
          .thenThrow(const DuplicateMemberException(<DuplicateMemberMatch>[]));
      final cubit = build();
      await fillAndCommit(cubit);
      expect(cubit.state.step, KioskSignupStep.stop);
      await cubit.close();
      verify(() => session.endFlow()).called(1);
    });
  });

  group('the member write (one call, both steps)', () {
    test('a successful create advances to the roster and marks BOTH detail '
        'steps committed', () async {
      final cubit = build();
      await fillAndCommit(cubit);

      final captured = verify(() => member.createMember(captureAny()))
          .captured
          .single as MembersManagementCreateRequest;
      expect(captured.firstName, 'Marcus');
      expect(captured.email, 'marcus.bell@gmail.com');
      expect(captured.dateOfBirth, '1994-04-12');
      expect(captured.address, '18 Mill St');
      expect(captured.emergencyContactName, 'Dana Bell');
      // Never a discount, never a saved card, never someone else's payer.
      expect(captured.paymentMethodId, isNull);
      expect(captured.allowDuplicate, isFalse);

      expect(cubit.state.step, KioskSignupStep.people);
      expect(cubit.state.payer.memberId, 'mem-new');
      expect(
        cubit.state.committedSteps,
        containsAll(<KioskSignupStep>[
          KioskSignupStep.details,
          KioskSignupStep.extraDetails,
        ]),
      );
      // The flow is NOT over — nothing releases the session here.
      verifyNever(() => session.endFlow());
      await cubit.close();
    });

    test('Skip carries typed values forward rather than discarding them',
        () async {
      final cubit = build();
      cubit.submitDetails(
        firstName: 'Marcus',
        lastName: 'Bell',
        email: 'marcus.bell@gmail.com',
      );
      // Skip is a permission label, never a discard: it lands on the identical
      // call with the identical values.
      await cubit.submitExtraDetails(address: '18 Mill St');

      final captured = verify(() => member.createMember(captureAny()))
          .captured
          .single as MembersManagementCreateRequest;
      expect(captured.address, '18 Mill St');
      expect(captured.dateOfBirth, isNull);
      await cubit.close();
    });

    blocTest<KioskSignupCubit, KioskSignupState>(
      'nothing is written before the extra-details step',
      build: build,
      act: (cubit) => cubit.submitDetails(
        firstName: 'Marcus',
        lastName: 'Bell',
        email: 'marcus.bell@gmail.com',
      ),
      verify: (cubit) {
        expect(cubit.state.step, KioskSignupStep.extraDetails);
        expect(cubit.state.payer.firstName, 'Marcus');
        // Creating on THIS step and PUTting the rest would cost a second
        // round trip and leave a written-then-abandoned member holding PII.
        verifyNever(() => member.createMember(any()));
      },
    );
  });

  group('ruling 11 — Back into a committed step never double-creates', () {
    test('Continue from a committed details step fires PUT, not a second '
        'create', () async {
      final cubit = build();
      await fillAndCommit(cubit);
      clearInteractions(member);

      cubit.back();
      expect(cubit.state.step, KioskSignupStep.extraDetails);
      cubit.back();
      expect(cubit.state.step, KioskSignupStep.details);
      cubit.submitDetails(
        firstName: 'Marcus',
        lastName: 'Bell',
        email: 'marcus@ironden.com',
      );
      await cubit.submitExtraDetails(dob: DateTime(1994, 4, 12));

      // A second create would 409 against the member's OWN just-created
      // account and dead-end them on the duplicate stop.
      verifyNever(() => member.createMember(any()));
      final captured =
          verify(() => member.updateMember('mem-new', captureAny()))
              .captured
              .single as MembersManagementUpdateRequest;
      expect(captured.email, 'marcus@ironden.com');
      expect(captured.dateOfBirth, '1994-04-12');
      expect(cubit.state.step, KioskSignupStep.people);
      await cubit.close();
    });
  });

  group('failures become terminal front-desk stops', () {
    test('a duplicate the member DECLINES stops the flow, exactly once',
        () async {
      when(() => member.createMember(any())).thenThrow(
        const DuplicateMemberException(<DuplicateMemberMatch>[
          DuplicateMemberMatch(
            memberId: 'mem-existing',
            firstName: 'Marcus',
            lastName: 'Bell',
            email: 'marcus.bell@gmail.com',
          ),
        ]),
      );
      final cubit = build();
      await fillAndCommit(cubit);

      // The 409 is an OFFER first: the flow is still live, nothing released.
      expect(cubit.state.step, KioskSignupStep.payerMatch);
      verifyNever(() => session.endFlow());

      cubit.declinePayerMatch();
      expect(cubit.state.step, KioskSignupStep.stop);
      expect(cubit.state.stopReason, KioskSignupStopReason.duplicateMember);
      // The 409's matches never reach the state as a LIST: rendering them
      // confirms accounts exist to whoever is at the shared iPad.
      expect(cubit.state.matches, isEmpty);
      expect(cubit.state.payer.memberId, isNull);
      verify(() => session.endFlow()).called(1);
      await cubit.close();
    });

    test('a duplicate that names NOBODY is terminal on the spot', () async {
      when(() => member.createMember(any()))
          .thenThrow(const DuplicateMemberException(<DuplicateMemberMatch>[]));
      final cubit = build();
      await fillAndCommit(cubit);

      // There is no offer anybody can answer, so there is nothing to ask.
      expect(cubit.state.step, KioskSignupStep.stop);
      expect(cubit.state.stopReason, KioskSignupStopReason.duplicateMember);
      expect(cubit.state.matchCandidate, isNull);
      verify(() => session.endFlow()).called(1);
      await cubit.close();
    });

    test('a 400 (gym has no Stripe Connect account) gets its own reason',
        () async {
      when(() => member.createMember(any())).thenThrow(
        ServerException('Server error 400', statusCode: 400),
      );
      final cubit = build();
      await fillAndCommit(cubit);

      expect(cubit.state.step, KioskSignupStep.stop);
      expect(
        cubit.state.stopReason,
        KioskSignupStopReason.paymentsUnavailable,
      );
      verify(() => session.endFlow()).called(1);
      await cubit.close();
    });

    test('any other failure lands on the generic stop', () async {
      when(() => member.createMember(any())).thenThrow(Exception('offline'));
      final cubit = build();
      await fillAndCommit(cubit);

      expect(cubit.state.step, KioskSignupStep.stop);
      expect(cubit.state.stopReason, KioskSignupStopReason.signupFailed);
      verify(() => session.endFlow()).called(1);
      await cubit.close();
    });

    test('the stop screen auto-returns after its hold', () {
      fakeAsync((async) {
        when(() => member.createMember(any()))
            .thenThrow(Exception('offline'));
        final cubit = build();
        cubit.submitDetails(
          firstName: 'Marcus',
          lastName: 'Bell',
          email: 'marcus.bell@gmail.com',
        );
        cubit.submitExtraDetails();
        async.flushMicrotasks();
        expect(cubit.state.stopCountdown, kKioskSignupStopHold.inSeconds);

        async.elapse(kKioskSignupStopHold + const Duration(seconds: 1));
        expect(cubit.state.abandoned, isTrue);
        // Still exactly once: the stop already released, and abandon()'s latch
        // holds however many exits run.
        verify(() => session.endFlow()).called(1);
        cubit.close();
      });
    });
  });

  group('the signup lane\'s own idle guard', () {
    test('5 minutes idle raises the warning, and the 30s countdown abandons',
        () {
      fakeAsync((async) {
        final cubit = build();
        cubit.submitDetails(
          firstName: 'Marcus',
          lastName: 'Bell',
          email: 'marcus.bell@gmail.com',
        );
        async.flushMicrotasks();

        async.elapse(kKioskIdleTimeout + const Duration(seconds: 1));
        expect(cubit.state.idleWarningActive, isTrue);
        expect(cubit.state.idleCountdown, kKioskIdleCountdown.inSeconds - 1);

        async.elapse(kKioskIdleCountdown);
        // Expiry abandons — `KioskSignupScreen` routes this to
        // `KioskFlowCubit.goHome()`, the kiosk's ONE abandon path.
        expect(cubit.state.abandoned, isTrue);
        expect(cubit.state.idleWarningActive, isFalse);
        verify(() => session.endFlow()).called(1);
        cubit.close();
      });
    });

    test('registerActivity dismisses the warning and resets the clock', () {
      fakeAsync((async) {
        final cubit = build();
        cubit.submitDetails(
          firstName: 'Marcus',
          lastName: 'Bell',
          email: 'marcus.bell@gmail.com',
        );
        async.flushMicrotasks();
        async.elapse(kKioskIdleTimeout + const Duration(seconds: 1));
        expect(cubit.state.idleWarningActive, isTrue);

        cubit.registerActivity();
        expect(cubit.state.idleWarningActive, isFalse);
        async.elapse(kKioskIdleCountdown + const Duration(seconds: 5));
        expect(cubit.state.abandoned, isFalse);
        cubit.close();
      });
    });

    test('suspendIdle stops the clock; resumeIdle re-arms a fresh 5 minutes',
        () {
      fakeAsync((async) {
        final cubit = build();
        cubit.suspendIdle();
        async.elapse(kKioskIdleTimeout * 3);
        expect(cubit.state.idleWarningActive, isFalse);

        cubit.resumeIdle();
        async.elapse(kKioskIdleTimeout + const Duration(seconds: 1));
        expect(cubit.state.idleWarningActive, isTrue);
        cubit.close();
      });
    });
  });

  group('abandon', () {
    // Plain tests, not `blocTest`: it closes the bloc before `verify`, and
    // `close()` legitimately releases the flow — which would mask exactly the
    // "did NOT release" assertion these make.
    test('the confirmation asks, and "Keep going" leaves the flow intact',
        () async {
      final cubit = build();
      cubit.askAbandon();
      expect(cubit.state.abandonConfirmActive, isTrue);

      cubit.dismissAbandon();
      expect(cubit.state.abandonConfirmActive, isFalse);
      expect(cubit.state.abandoned, isFalse);
      // The safe answer must not end anything.
      verifyNever(() => session.endFlow());
      await cubit.close();
    });

    test('abandon releases the flow and raises the go-home signal', () async {
      final cubit = build();
      cubit.abandon();
      expect(cubit.state.abandoned, isTrue);
      verify(() => session.endFlow()).called(1);
      await cubit.close();
      // Still exactly once after the teardown — the latch holds.
      verifyNever(() => session.endFlow());
    });
  });

  group('the plan catalogue warmed at entry', () {
    test('keeps only public, priced plans', () async {
      when(() => memberships.listPlans(any())).thenAnswer(
        (_) async => [
          _plan('p-public-priced', isPublic: true, priced: true),
          _plan('p-public-unpriced', isPublic: true, priced: false),
          _plan('p-private-priced', isPublic: false, priced: true),
        ],
      );
      final cubit = build();
      await Future<void>.delayed(Duration.zero);
      expect(
        cubit.state.plans.map((p) => p.planId),
        ['p-public-priced'],
      );
      expect(cubit.state.plansFailed, isFalse);
      await cubit.close();
    });

    test('a failed warm is non-fatal — the step retries, the flow lives on',
        () async {
      when(() => memberships.listPlans(any())).thenThrow(Exception('down'));
      final cubit = build();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.plansFailed, isTrue);
      // A failed warm never moves the member off the lane's first fork.
      expect(cubit.state.step, KioskSignupStep.entry);
      await cubit.close();
    });
  });
}

MembershipPlanResponse _plan(
  String id, {
  required bool isPublic,
  required bool priced,
}) {
  return MembershipPlanResponse(
    planId: id,
    gymId: 'gym-1',
    planName: id,
    imageUrl: 'https://cdn/plan.png',
    planType: PlanType.recurring,
    isPublic: isPublic,
    createdAt: DateTime.utc(2026),
    activePrice: priced
        ? MembershipPlanPriceResponse(
            priceId: '$id-price',
            planId: id,
            gymId: 'gym-1',
            stripePriceId: 'price_$id',
            price: 14900,
            isActive: true,
            createdAt: DateTime.utc(2026),
          )
        : null,
  );
}
