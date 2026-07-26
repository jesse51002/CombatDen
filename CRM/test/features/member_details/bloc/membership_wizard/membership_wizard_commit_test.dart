import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_cubit.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_outcome.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_step.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_status.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/member_details/data/models/proration_behavior.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/custom_card_capture.dart';

import 'membership_wizard_fixtures.dart';

/// The money moment. Every test here is a double-charge defence: the flow's
/// one call takes a real payer's money, and the old wizard shipped without a
/// single one of these.
void main() {
  late MockMemberRepository member;
  late MockMembershipsRepository memberships;

  final recurringPlan = plan(planId: 'plan-a', priceId: 'price-a');
  final packPlan = plan(
    planId: 'plan-b',
    priceId: 'price-b',
    type: PlanType.oneTime,
    price: 5000,
  );

  const oneOffCard = CustomCardCapture(
    pmId: 'pm_123',
    brand: 'Visa',
    lastFour: '4242',
  );

  setUpAll(registerWizardFallbacks);

  setUp(() {
    member = MockMemberRepository();
    memberships = MockMembershipsRepository();
    when(() => member.listMembershipPlans(any()))
        .thenAnswer((_) async => [recurringPlan, packPlan]);
    when(() => member.listGymDiscounts(any())).thenAnswer((_) async => []);
    when(() => memberships.listMemberWaiverStatus(any(), any()))
        .thenAnswer((_) async => []);
    when(() => member.previewStartMemberships(any()))
        .thenAnswer((_) async => startPreview(recurring: invoice()));
    when(() => member.getMemberDetail('m-child'))
        .thenAnswer((_) async => detail(memberId: 'm-child'));
    when(() => member.startMemberships(any())).thenAnswer(
      (_) async => startResponse([
        resultItem(memberId: 'm-payer', planId: 'plan-a'),
      ]),
    );
  });

  /// A solo run at the payment step, ready to pay.
  Future<MembershipWizardCubit> atPayment({
    bool packOnly = false,
  }) async {
    final cubit = buildWizard(
      member: member,
      memberships: memberships,
      launchMember: detail(card: savedCard),
    );
    await cubit.open();
    await cubit.next();
    cubit.togglePlan(packOnly ? packPlan : recurringPlan);
    await cubit.next();
    await cubit.next();
    expect(cubit.state.step, MembershipWizardStep.payment);
    return cubit;
  }

  /// A payer + child run, one membership each, at the payment step.
  Future<MembershipWizardCubit> familyAtPayment() async {
    final cubit = buildWizard(
      member: member,
      memberships: memberships,
      launchMember: detail(
        card: savedCard,
        authorizedToPayFor: [linked(memberId: 'm-child')],
      ),
      initialTrainingMemberIds: const {'m-payer', 'm-child'},
    );
    await cubit.open();
    await cubit.next();
    cubit.togglePlan(recurringPlan);
    await cubit.next();
    cubit.togglePlan(packPlan);
    await cubit.next();
    await cubit.next();
    return cubit;
  }

  MemberMembershipsStartRequest lastPosted() => verify(
        () => member.startMemberships(captureAny()),
      ).captured.last as MemberMembershipsStartRequest;

  List<MemberMembershipsStartRequest> allPosted() => verify(
        () => member.startMemberships(captureAny()),
      ).captured.cast<MemberMembershipsStartRequest>();

  group('the request the money rides on', () {
    test('cash carries the flag and no card', () async {
      final cubit = await atPayment();
      cubit.setPaidWithCash(true);
      await cubit.pay();

      final posted = lastPosted();
      expect(posted.paidWithCash, isTrue);
      expect(posted.payment, isNull);
      expect(posted.payerMemberId, 'm-payer');
      expect(posted.gymId, kGymId);
      await cubit.close();
    });

    test('the saved card carries no payment object at all', () async {
      final cubit = await atPayment();
      await cubit.pay();

      final posted = lastPosted();
      expect(posted.paidWithCash, isFalse);
      expect(
        posted.payment,
        isNull,
        reason: 'a recurring membership bills the payer\'s saved default',
      );
      await cubit.close();
    });

    test('the one-off card rides ONLY on !cash ∧ hasOneTime ∧ !hasRecurring',
        () async {
      final cubit = await atPayment(packOnly: true);
      cubit.setCustomCard(oneOffCard);
      await cubit.pay();

      final posted = lastPosted();
      expect(posted.payment, isNotNull);
      expect(posted.payment!.paymentMethodId, 'pm_123');
      expect(
        posted.payment!.setDefault,
        isFalse,
        reason: 'it pays today\'s one-time invoice once and is never saved',
      );
      await cubit.close();
    });

    test('the one-off card is DROPPED from the wire once cash goes on',
        () async {
      final cubit = await atPayment(packOnly: true);
      cubit.setCustomCard(oneOffCard);
      cubit.setPaidWithCash(true);
      await cubit.pay();

      final posted = lastPosted();
      expect(posted.payment, isNull);
      expect(posted.paidWithCash, isTrue);
      // The card is still HELD — the block is a stated reason, not a deletion.
      expect(cubit.state.customCard, isNotNull);
      await cubit.close();
    });

    test('the one-off card is DROPPED from the wire once the cart turns '
        'recurring', () async {
      final cubit = await atPayment(packOnly: true);
      cubit.setCustomCard(oneOffCard);
      cubit.editFromReview('m-payer');
      cubit.togglePlan(recurringPlan);
      await cubit.next();
      await cubit.next();
      await cubit.pay();

      expect(lastPosted().payment, isNull);
      await cubit.close();
    });

    test('PAY submits the CHOSEN proration, not the preview\'s', () async {
      final cubit = await atPayment();
      await cubit.back();
      cubit.setProration(ProrationBehavior.noCharge);
      await cubit.next();
      await cubit.pay();

      expect(lastPosted().prorationBehavior, ProrationBehavior.noCharge);
      await cubit.close();
    });
  });

  group('the double-charge defences', () {
    test('a double tap on PAY posts exactly ONE request', () async {
      final cubit = await atPayment();
      final first = cubit.pay();
      final second = cubit.pay();
      await Future.wait([first, second]);

      verify(() => member.startMemberships(any())).called(1);
      await cubit.close();
    });

    test('a key that already went out is NEVER re-posted', () async {
      final cubit = await atPayment();
      await cubit.pay();
      verify(() => member.startMemberships(any())).called(1);

      // The desk presses PAY again after an unknown outcome. Re-posting the
      // same key is the one action that could take the money twice.
      await cubit.pay();
      verifyNever(() => member.startMemberships(any()));
      expect(cubit.state.commitError, MembershipWizardCommitError.unconfirmed);
      expect(cubit.state.step, MembershipWizardStep.results);
      await cubit.close();
    });

    test('a retry sends ONLY the un-created items, under a FRESH key',
        () async {
      when(() => member.startMemberships(any())).thenAnswer(
        (_) async => startResponse([
          resultItem(memberId: 'm-payer', planId: 'plan-a'),
          resultItem(
            memberId: 'm-child',
            planId: 'plan-b',
            planType: PlanType.oneTime,
            status: MemberMembershipsStartStatus.failed,
          ),
        ]),
      );
      final cubit = await familyAtPayment();
      await cubit.pay();
      expect(cubit.state.outcome, MembershipWizardOutcome.partial);
      expect(cubit.state.canRetry, isTrue);
      expect(cubit.state.alreadyStarted('m-payer', 'plan-a'), isTrue);

      when(() => member.startMemberships(any())).thenAnswer(
        (_) async => startResponse([
          resultItem(
            memberId: 'm-child',
            planId: 'plan-b',
            planType: PlanType.oneTime,
          ),
        ]),
      );
      await cubit.retryUncreated();

      final posted = allPosted();
      expect(posted.length, 2);
      expect(posted.first.memberships.length, 2);
      expect(
        posted.last.memberships.map((i) => i.memberId),
        ['m-child'],
        reason: 're-sending the created one would charge for it twice',
      );
      expect(
        posted.last.idempotencyKey,
        isNot(posted.first.idempotencyKey),
        reason: 'reusing the sent key would only trip the latch',
      );
      await cubit.close();
    });

    test('the receipt keeps what an EARLIER attempt created', () async {
      when(() => member.startMemberships(any())).thenAnswer(
        (_) async => startResponse([
          resultItem(memberId: 'm-payer', planId: 'plan-a'),
          resultItem(
            memberId: 'm-child',
            planId: 'plan-b',
            planType: PlanType.oneTime,
            status: MemberMembershipsStartStatus.failed,
          ),
        ]),
      );
      final cubit = await familyAtPayment();
      await cubit.pay();

      when(() => member.startMemberships(any())).thenAnswer(
        (_) async => startResponse([
          resultItem(
            memberId: 'm-child',
            planId: 'plan-b',
            planType: PlanType.oneTime,
          ),
        ]),
      );
      await cubit.retryUncreated();

      expect(cubit.state.startItems.length, 2);
      expect(cubit.state.outcome, MembershipWizardOutcome.allCreated);
      expect(
        cubit.state.canRetry,
        isFalse,
        reason: 'an all-created receipt has nothing left to send',
      );
      await cubit.close();
    });

    test('an all-created run offers no retry at all', () async {
      final cubit = await atPayment();
      await cubit.pay();
      expect(cubit.state.outcome, MembershipWizardOutcome.allCreated);
      expect(cubit.state.canRetry, isFalse);

      await cubit.retryUncreated();
      verify(() => member.startMemberships(any())).called(1);
      await cubit.close();
    });

    test('an `unknown` row keeps the retry alive but claims nothing',
        () async {
      when(() => member.startMemberships(any())).thenAnswer(
        (_) async => startResponse([
          resultItem(memberId: 'm-payer', planId: 'plan-a'),
          resultItem(
            memberId: 'm-child',
            planId: 'plan-b',
            planType: PlanType.oneTime,
            status: MemberMembershipsStartStatus.unknown,
          ),
        ]),
      );
      final cubit = await familyAtPayment();
      await cubit.pay();

      expect(
        cubit.state.outcome,
        MembershipWizardOutcome.partial,
        reason: 'never all-created — the backend would not confirm the row',
      );
      expect(cubit.state.retryScope, {'m-child·plan-b'});
      expect(cubit.state.alreadyStarted('m-child', 'plan-b'), isFalse);
      await cubit.close();
    });
  });

  group('the three-way split of a landed start', () {
    test('all created', () async {
      final cubit = await atPayment();
      await cubit.pay();
      expect(cubit.state.outcome, MembershipWizardOutcome.allCreated);
      expect(cubit.state.commitError, isNull);
      expect(cubit.state.starting, isFalse);
      await cubit.close();
    });

    test('all failed — the one case where nothing was charged', () async {
      when(() => member.startMemberships(any())).thenAnswer(
        (_) async => startResponse(
          [
            resultItem(
              memberId: 'm-payer',
              planId: 'plan-a',
              status: MemberMembershipsStartStatus.failed,
            ),
          ],
          chargeCount: 0,
        ),
      );
      final cubit = await atPayment();
      await cubit.pay();
      expect(cubit.state.outcome, MembershipWizardOutcome.allFailed);
      expect(cubit.state.canRetry, isTrue);
      await cubit.close();
    });

    test('partial — money HAS moved for the group that cleared', () async {
      when(() => member.startMemberships(any())).thenAnswer(
        (_) async => startResponse([
          resultItem(memberId: 'm-payer', planId: 'plan-a'),
          resultItem(
            memberId: 'm-child',
            planId: 'plan-b',
            planType: PlanType.oneTime,
            status: MemberMembershipsStartStatus.failed,
          ),
        ]),
      );
      final cubit = await familyAtPayment();
      await cubit.pay();
      expect(cubit.state.outcome, MembershipWizardOutcome.partial);
      await cubit.close();
    });
  });

  group('a commit that produced no breakdown', () {
    test('a 409 replay says the ORIGINAL start stands', () async {
      when(() => member.startMemberships(any()))
          .thenThrow(const ServerException('replay', statusCode: 409));
      final cubit = await atPayment();
      await cubit.pay();

      expect(
        cubit.state.commitError,
        MembershipWizardCommitError.alreadyStarted,
      );
      expect(cubit.state.starting, isFalse);
      expect(cubit.state.step, MembershipWizardStep.results);
      await cubit.close();
    });

    test('a failed retry does NOT erase the earlier attempt\'s receipt',
        () async {
      when(() => member.startMemberships(any())).thenAnswer(
        (_) async => startResponse([
          resultItem(memberId: 'm-payer', planId: 'plan-a'),
          resultItem(
            memberId: 'm-child',
            planId: 'plan-b',
            planType: PlanType.oneTime,
            status: MemberMembershipsStartStatus.failed,
          ),
        ]),
      );
      final cubit = await familyAtPayment();
      await cubit.pay();

      when(() => member.startMemberships(any()))
          .thenThrow(const ServerException('down', statusCode: 500));
      await cubit.retryUncreated();

      expect(cubit.state.commitError, MembershipWizardCommitError.failed);
      expect(cubit.state.startItems.length, 2);
      expect(cubit.state.outcome, MembershipWizardOutcome.partial);
      await cubit.close();
    });

    test('an emptied cart sends NOTHING rather than re-posting it', () async {
      final cubit = await atPayment();
      cubit.editFromReview('m-payer');
      cubit.togglePlan(recurringPlan);
      expect(cubit.state.pendingItems, isEmpty);

      await cubit.pay();
      verifyNever(() => member.startMemberships(any()));
      expect(
        cubit.state.commitError,
        MembershipWizardCommitError.nothingToSend,
      );
      await cubit.close();
    });

    test('the error is dismissible so the step can be offered again',
        () async {
      when(() => member.startMemberships(any()))
          .thenThrow(const ServerException('down', statusCode: 500));
      final cubit = await atPayment();
      await cubit.pay();
      expect(cubit.state.commitError, MembershipWizardCommitError.failed);
      cubit.clearCommitError();
      expect(cubit.state.commitError, isNull);
      await cubit.close();
    });
  });

  test('a 422 at PAY routes to the waiver run — the backstop', () async {
    when(() => member.startMemberships(any())).thenThrow(
      const WaiverGateException(
        message: 'Unsigned waivers',
        unsigned: [
          WaiverGateItem(
            memberId: 'm-payer',
            waiverId: 'waiver-late',
            name: 'Liability release',
          ),
        ],
      ),
    );
    when(() => memberships.getWaiver(any(), any()))
        .thenAnswer((_) async => waiver(waiverId: 'waiver-late'));

    final cubit = await atPayment();
    await cubit.pay();

    expect(cubit.state.step, MembershipWizardStep.waivers);
    expect(cubit.state.starting, isFalse);
    expect(cubit.state.waiverQueue.single.waiverId, 'waiver-late');
    await cubit.close();
  });
}
