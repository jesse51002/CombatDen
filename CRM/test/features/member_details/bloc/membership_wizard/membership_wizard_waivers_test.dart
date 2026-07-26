import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_cubit.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_step.dart';
import 'package:crm/features/memberships/data/models/member_waiver_status.dart';
import 'package:crm/features/memberships/data/models/waiver_signature_response.dart';
import 'package:crm/features/memberships/data/models/waiver_type.dart';

import 'membership_wizard_fixtures.dart';

class _MockSignature extends Mock implements WaiverSignatureResponse {}

MemberWaiverStatus status({
  required String waiverId,
  bool signed = true,
  bool meetsFloor = true,
}) =>
    MemberWaiverStatus(
      waiverId: waiverId,
      name: 'Liability release',
      waiverType: WaiverType.custom,
      signed: signed,
      meetsFloor: meetsFloor,
    );

/// The waiver run — a REAL step before the money, derived from the plans that
/// were picked. The old wizard learned about a missing signature only when the
/// money call came back 422, which put a legal step after the price.
void main() {
  late MockMemberRepository member;
  late MockMembershipsRepository memberships;

  final gated = plan(
    planId: 'plan-a',
    priceId: 'price-a',
    waiverIds: const ['waiver-1', 'waiver-2'],
  );
  final ungated = plan(planId: 'plan-b', priceId: 'price-b');

  setUpAll(registerWizardFallbacks);

  setUp(() {
    member = MockMemberRepository();
    memberships = MockMembershipsRepository();
    when(() => member.listMembershipPlans(any()))
        .thenAnswer((_) async => [gated, ungated]);
    when(() => member.listGymDiscounts(any())).thenAnswer((_) async => []);
    when(() => member.previewStartMemberships(any()))
        .thenAnswer((_) async => startPreview(recurring: invoice()));
    when(() => memberships.listMemberWaiverStatus(any(), any()))
        .thenAnswer((_) async => []);
    when(() => memberships.getWaiver(any(), any()))
        .thenAnswer((call) async =>
            waiver(waiverId: call.positionalArguments.first as String));
    when(
      () => memberships.recordWaiverSignature(
        waiverId: any(named: 'waiverId'),
        gymId: any(named: 'gymId'),
        memberId: any(named: 'memberId'),
        waiverVersionId: any(named: 'waiverVersionId'),
        signerName: any(named: 'signerName'),
      ),
    ).thenAnswer((_) async => _MockSignature());
  });

  Future<MembershipWizardCubit> soloAtPlans() async {
    final cubit = buildWizard(
      member: member,
      memberships: memberships,
      launchMember: detail(),
    );
    await cubit.open();
    await cubit.next();
    return cubit;
  }

  test('the queue appears BEFORE the money, from the picked plan alone',
      () async {
    final cubit = await soloAtPlans();
    expect(cubit.state.hasWaivers, isFalse);

    cubit.togglePlan(gated);
    expect(
      cubit.state.waiverQueue.map((t) => t.waiverId),
      ['waiver-1', 'waiver-2'],
      reason: 'nothing was posted and no 422 has fired',
    );
    expect(cubit.state.steps, contains(MembershipWizardStep.waivers));

    await cubit.next();
    expect(cubit.state.step, MembershipWizardStep.waivers);
    verifyNever(() => member.previewStartMemberships(any()));
    await cubit.close();
  });

  test('un-picking the plan takes its signatures back off the run', () async {
    final cubit = await soloAtPlans();
    cubit.togglePlan(gated);
    expect(cubit.state.hasWaivers, isTrue);
    cubit.togglePlan(gated);
    cubit.togglePlan(ungated);
    expect(cubit.state.hasWaivers, isFalse);
    await cubit.close();
  });

  test('drops a waiver the SERVER cleared at or above the re-sign floor',
      () async {
    when(() => memberships.listMemberWaiverStatus('m-payer', kGymId))
        .thenAnswer((_) async => [status(waiverId: 'waiver-1')]);
    final cubit = await soloAtPlans();
    cubit.togglePlan(gated);
    expect(
      cubit.state.waiverQueue.map((t) => t.waiverId),
      ['waiver-2'],
      reason: '"waiver 1 of 1" must count the signatures about to be given',
    );
    await cubit.close();
  });

  test('keeps a signature that sits BELOW the floor', () async {
    when(() => memberships.listMemberWaiverStatus('m-payer', kGymId))
        .thenAnswer(
      (_) async => [status(waiverId: 'waiver-1', meetsFloor: false)],
    );
    final cubit = await soloAtPlans();
    cubit.togglePlan(gated);
    expect(
      cubit.state.waiverQueue.map((t) => t.waiverId),
      ['waiver-1', 'waiver-2'],
    );
    await cubit.close();
  });

  test('FAILS CLOSED when the prior-signature read does not land', () async {
    when(() => memberships.listMemberWaiverStatus(any(), any()))
        .thenThrow(const ServerException('down', statusCode: 500));
    final cubit = await soloAtPlans();
    cubit.togglePlan(gated);
    expect(
      cubit.state.waiverQueue.length,
      2,
      reason: 'a missing signature voids the gym\'s protection; a needless '
          'one costs twenty seconds',
    );
    await cubit.close();
  });

  test('signing advances the run, and signed stays signed', () async {
    final cubit = await soloAtPlans();
    cubit.togglePlan(gated);
    await cubit.next();
    expect(cubit.state.currentWaiverTask?.waiverId, 'waiver-1');
    expect(cubit.state.waiver?.waiverId, 'waiver-1');
    expect(cubit.state.canAdvance, isFalse);

    await cubit.signCurrentWaiver(signerName: 'Marcus Bell');
    expect(cubit.state.currentWaiverTask?.waiverId, 'waiver-2');

    await cubit.signCurrentWaiver(signerName: 'Marcus Bell');
    expect(cubit.state.allWaiversSigned, isTrue);
    expect(cubit.state.canAdvance, isTrue);

    // Back into the run and forward again must not re-ask.
    await cubit.next();
    expect(cubit.state.step, MembershipWizardStep.reviewCharges);
    await cubit.back();
    expect(cubit.state.step, MembershipWizardStep.plans);
    await cubit.next();
    expect(
      cubit.state.step,
      MembershipWizardStep.waivers,
      reason: 'the step still exists — it simply has nothing left to ask',
    );
    expect(cubit.state.allWaiversSigned, isTrue);
    await cubit.close();
  });

  test('a refused signature reloads the body rather than recording it',
      () async {
    final cubit = await soloAtPlans();
    cubit.togglePlan(gated);
    await cubit.next();
    when(
      () => memberships.recordWaiverSignature(
        waiverId: any(named: 'waiverId'),
        gymId: any(named: 'gymId'),
        memberId: any(named: 'memberId'),
        waiverVersionId: any(named: 'waiverVersionId'),
        signerName: any(named: 'signerName'),
      ),
    ).thenThrow(const WaiverStaleVersionException());

    await cubit.signCurrentWaiver(signerName: 'Marcus Bell');
    expect(cubit.state.waiverStale, isTrue);
    expect(cubit.state.signedWaiverKeys, isEmpty);
    expect(cubit.state.currentWaiverTask?.waiverId, 'waiver-1');
    await cubit.close();
  });

  test('the 422 stays the BACKSTOP and is authoritative', () async {
    // A plan whose waiver list drifted from the gate: the client sees nothing
    // to sign and walks straight at the money.
    final cubit = await soloAtPlans();
    cubit.togglePlan(ungated);
    when(() => member.previewStartMemberships(any())).thenThrow(
      const WaiverGateException(
        message: 'Unsigned waivers',
        unsigned: [
          WaiverGateItem(
            memberId: 'm-payer',
            waiverId: 'waiver-drift',
            name: 'Photo release',
          ),
        ],
      ),
    );

    await cubit.next();
    expect(cubit.state.step, MembershipWizardStep.waivers);
    expect(cubit.state.waiverQueue.single.waiverId, 'waiver-drift');
    expect(cubit.state.waiverQueue.single.serverGated, isTrue);
    expect(cubit.state.waiverQueue.single.waiverName, 'Photo release');
    await cubit.close();
  });

  test('a gate DROPS this run\'s own mark on the pair it names', () async {
    when(() => memberships.listMemberWaiverStatus('m-payer', kGymId))
        .thenAnswer((_) async => []);
    final cubit = await soloAtPlans();
    cubit.togglePlan(gated);
    await cubit.next();
    await cubit.signCurrentWaiver(signerName: 'Marcus Bell');
    await cubit.signCurrentWaiver(signerName: 'Marcus Bell');
    expect(cubit.state.signedWaiverKeys.length, 2);

    when(() => member.previewStartMemberships(any())).thenThrow(
      const WaiverGateException(
        message: 'Unsigned waivers',
        unsigned: [
          WaiverGateItem(
            memberId: 'm-payer',
            waiverId: 'waiver-2',
            name: 'Liability release',
          ),
        ],
      ),
    );
    await cubit.next();

    expect(cubit.state.step, MembershipWizardStep.waivers);
    expect(
      cubit.state.signedWaiverKeys,
      {'m-payer:waiver-1'},
      reason: 'the server is authoritative — skipping what it blocks on loops '
          'the desk forever',
    );
    expect(cubit.state.currentWaiverTask?.waiverId, 'waiver-2');
    await cubit.close();
  });

  test('a gate naming somebody off the roster is still asked for', () async {
    final cubit = await soloAtPlans();
    cubit.togglePlan(ungated);
    when(() => member.previewStartMemberships(any())).thenThrow(
      const WaiverGateException(
        message: 'Unsigned waivers',
        unsigned: [
          WaiverGateItem(
            memberId: 'm-stranger',
            waiverId: 'waiver-x',
            name: 'Liability release',
          ),
        ],
      ),
    );
    await cubit.next();
    expect(cubit.state.waiverQueue.single.memberId, 'm-stranger');
    await cubit.close();
  });

  test('a failed waiver body read is an inline retry, never a dead end',
      () async {
    final cubit = await soloAtPlans();
    cubit.togglePlan(gated);
    when(() => memberships.getWaiver(any(), any()))
        .thenThrow(const ServerException('down', statusCode: 500));
    await cubit.next();
    expect(cubit.state.waiverLoad.isFailed, isTrue);
    expect(cubit.state.waiverLoad.message, isNotEmpty);

    when(() => memberships.getWaiver(any(), any()))
        .thenAnswer((_) async => waiver());
    await cubit.retryWaiver();
    expect(cubit.state.waiverLoad.isReady, isTrue);
    await cubit.close();
  });
}
