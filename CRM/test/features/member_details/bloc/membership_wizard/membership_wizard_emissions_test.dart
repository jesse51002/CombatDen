import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_cubit.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_outcome.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_state.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_step.dart';

import 'membership_wizard_fixtures.dart';

/// The SEQUENCES a surface renders off — a step that shows a spinner and then
/// an error is a different screen from one that shows an error immediately,
/// and only the emitted order tells them apart.
void main() {
  late MockMemberRepository member;
  late MockMembershipsRepository memberships;

  final unlimited = plan(planId: 'plan-a', priceId: 'price-a');

  setUpAll(registerWizardFallbacks);

  setUp(() {
    member = MockMemberRepository();
    memberships = MockMembershipsRepository();
    when(() => member.listGymDiscounts(any())).thenAnswer((_) async => []);
    when(() => memberships.listMemberWaiverStatus(any(), any()))
        .thenAnswer((_) async => []);
    when(() => member.previewStartMemberships(any()))
        .thenAnswer((_) async => startPreview(recurring: invoice()));
    when(() => member.startMemberships(any())).thenAnswer(
      (_) async =>
          startResponse([resultItem(memberId: 'm-payer', planId: 'plan-a')]),
    );
  });

  MembershipWizardCubit build() => buildWizard(
        member: member,
        memberships: memberships,
        launchMember: detail(card: savedCard),
      );

  blocTest<MembershipWizardCubit, MembershipWizardState>(
    'the catalogue read emits loading then ready',
    setUp: () {
      when(() => member.listMembershipPlans(any()))
          .thenAnswer((_) async => [unlimited]);
    },
    build: build,
    act: (cubit) => cubit.loadCatalogue(),
    expect: () => [
      isA<MembershipWizardState>()
          .having((s) => s.plansLoad.isLoading, 'loading', isTrue),
      isA<MembershipWizardState>()
          .having((s) => s.plansLoad.isReady, 'ready', isTrue)
          .having((s) => s.plans.length, 'offered plans', 1),
    ],
  );

  blocTest<MembershipWizardCubit, MembershipWizardState>(
    'a failed catalogue read emits loading then a MESSAGE, never a bare null',
    setUp: () {
      when(() => member.listMembershipPlans(any()))
          .thenThrow(const ServerException('down', statusCode: 500));
    },
    build: build,
    act: (cubit) => cubit.loadCatalogue(),
    expect: () => [
      isA<MembershipWizardState>()
          .having((s) => s.plansLoad.isLoading, 'loading', isTrue),
      isA<MembershipWizardState>()
          .having((s) => s.plansLoad.isFailed, 'failed', isTrue)
          .having((s) => s.plansLoad.message, 'message', isNotEmpty),
    ],
  );

  test('PAY emits `starting` BEFORE the call and the breakdown after it',
      () async {
    when(() => member.listMembershipPlans(any()))
        .thenAnswer((_) async => [unlimited]);
    final cubit = build();
    await cubit.open();
    await cubit.next();
    cubit.togglePlan(unlimited);
    await cubit.next();
    await cubit.next();

    // Recorded from the payment step only, so the sequence under test is the
    // money one rather than the whole walk to it.
    final emitted = <MembershipWizardState>[];
    final sub = cubit.stream.listen(emitted.add);
    await cubit.pay();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(emitted.length, 2);
    expect(emitted.first.starting, isTrue);
    expect(emitted.first.step, MembershipWizardStep.results);
    expect(
      emitted.first.startResult,
      isNull,
      reason: 'the spinner may never sit under a stale breakdown',
    );
    expect(emitted.last.starting, isFalse);
    expect(emitted.last.outcome, MembershipWizardOutcome.allCreated);
    await cubit.close();
  });
}
