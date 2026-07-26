import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_cubit.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/waivers_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/features/memberships/data/models/waiver_signature_response.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_sign_panel.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_waiver_doc_panel.dart';

import '../../../../bloc/membership_wizard/membership_wizard_fixtures.dart';
import 'wizard_step_harness.dart';

class _MockSignatureResponse extends Mock implements WaiverSignatureResponse {}

/// The waiver run, rendered.
///
/// One pair at a time with the WHOLE run listed beside it, and the invariant
/// that is legal rather than cosmetic: the typed name and the consent tick are
/// cleared the moment the pair changes, so a signature can never carry from
/// one person to the next.
void main() {
  late MockMemberRepository member;
  late MockMembershipsRepository memberships;
  late RecordedWizardActions recorded;

  final signedPlan = plan(
    planId: 'plan-w',
    priceId: 'price-w',
    name: 'Unlimited Monthly',
    waiverIds: const ['waiver-1'],
  );

  setUpAll(registerWizardFallbacks);

  setUp(() {
    recorded = RecordedWizardActions();
    member = MockMemberRepository();
    memberships = MockMembershipsRepository();
    when(() => member.listMembershipPlans(any()))
        .thenAnswer((_) async => [signedPlan]);
    when(() => member.listGymDiscounts(any())).thenAnswer((_) async => []);
    when(() => member.previewStartMemberships(any()))
        .thenAnswer((_) async => startPreview(recurring: invoice()));
    when(() => member.getMemberDetail('m-child')).thenAnswer(
      (_) async => detail(memberId: 'm-child', firstName: 'Ella'),
    );
    when(() => memberships.listMemberWaiverStatus(any(), any()))
        .thenAnswer((_) async => []);
    when(() => memberships.getWaiver(any(), any()))
        .thenAnswer((_) async => waiver());
    when(
      () => memberships.recordWaiverSignature(
        waiverId: any(named: 'waiverId'),
        gymId: any(named: 'gymId'),
        memberId: any(named: 'memberId'),
        waiverVersionId: any(named: 'waiverVersionId'),
        signerName: any(named: 'signerName'),
      ),
    ).thenAnswer((_) async => _MockSignatureResponse());
  });

  /// Marcus and Ella, one waiver owed each, standing on the run's first pair.
  Future<MembershipWizardCubit> atWaivers() async {
    final cubit = buildWizard(
      member: member,
      memberships: memberships,
      launchMember: detail(
        authorizedToPayFor: [linked(memberId: 'm-child', firstName: 'Ella')],
      ),
      initialTrainingMemberIds: const {'m-payer', 'm-child'},
    );
    await cubit.open();
    await cubit.next();
    cubit.togglePlan(signedPlan);
    await cubit.next();
    cubit.togglePlan(signedPlan);
    await cubit.next();
    expect(cubit.state.step, MembershipWizardStep.waivers);
    return cubit;
  }

  Future<void> pumpStep(
    WidgetTester tester,
    MembershipWizardCubit cubit,
  ) =>
      pumpWizardStep(
        tester,
        cubit: cubit,
        step: WizardWaiversStep(
          showAddMemberGroup: false,
          actions: recorded.actions,
        ),
      );

  String signerText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller?.text ?? '';

  testWidgets('renders the document, the signing panel, and the WHOLE run '
      'with its marks', (tester) async {
    final cubit = await atWaivers();
    await pumpStep(tester, cubit);

    expect(find.byType(FlowWaiverDocPanel), findsOneWidget);
    expect(find.byType(FlowSignPanel), findsOneWidget);
    expect(find.text(WizardWaiversCopy.runEyebrow), findsOneWidget);

    // Both signatures listed, each named for whose it is.
    expect(cubit.state.waiverQueue, hasLength(2));
    expect(find.text(WizardWaiversCopy.forMember('Marcus Bell')),
        findsOneWidget);
    expect(find.text(WizardWaiversCopy.forMember('Ella Bell')), findsOneWidget);
    expect(find.text(WizardWaiversCopy.signingNowPill), findsOneWidget);
    expect(find.text(WizardWaiversCopy.nextPill), findsOneWidget);
    expect(find.text(WizardWaiversCopy.signedPill), findsNothing);

    await cubit.signCurrentWaiver(signerName: 'Marcus Bell');
    await tester.pumpAndSettle();

    expect(
      find.text(WizardWaiversCopy.signedPill),
      findsOneWidget,
      reason: 'a signed entry stays on the list — it must not shrink under '
          'somebody mid-run',
    );
    expect(find.text(WizardWaiversCopy.signingNowPill), findsOneWidget);
    expect(find.text(WizardWaiversCopy.nextPill), findsNothing);
    await cubit.close();
  });

  testWidgets('the primary stays closed until the name is typed AND consent '
      'is ticked', (tester) async {
    final cubit = await atWaivers();
    await pumpStep(tester, cubit);

    expect(find.byType(TextField), findsOneWidget);
    expect(
      wizardPrimary(tester, WizardWaiversCopy.signAction).onPressed,
      isNull,
    );

    await tester.enterText(find.byType(TextField), 'Marcus Bell');
    await tester.pumpAndSettle();
    expect(
      wizardPrimary(tester, WizardWaiversCopy.signAction).onPressed,
      isNull,
      reason: 'a typed name without the acknowledgement is not a signature',
    );

    await tester.tap(find.text(staffCopy.signingConsentLabel));
    await tester.pumpAndSettle();
    expect(
      wizardPrimary(tester, WizardWaiversCopy.signAction).onPressed,
      isNotNull,
    );
    await cubit.close();
  });

  testWidgets('the typed name and the consent tick are CLEARED when the pair '
      'changes', (tester) async {
    final cubit = await atWaivers();
    await pumpStep(tester, cubit);

    await tester.enterText(find.byType(TextField), 'Marcus Bell');
    await tester.tap(find.text(staffCopy.signingConsentLabel));
    await tester.pumpAndSettle();

    await tester.tap(find.text(WizardWaiversCopy.signAction));
    await tester.pumpAndSettle();

    expect(cubit.state.currentWaiverTask?.memberId, 'm-child');
    expect(
      signerText(tester),
      isEmpty,
      reason: 'a carried-over name records somebody as signing a document '
          'they never typed their name on',
    );
    expect(
      wizardPrimary(tester, WizardWaiversCopy.signAction).onPressed,
      isNull,
      reason: 'the consent tick is cleared with it',
    );
    // The identity band moves to whose signature is now being taken.
    expect(find.text(WizardWaiversCopy.signingForEyebrow), findsWidgets);
    expect(find.text('Ella Bell'), findsWidgets);
    await cubit.close();
  });

  testWidgets('a failed waiver body read offers a retry, and Try again reads '
      'again', (tester) async {
    when(() => memberships.getWaiver(any(), any()))
        .thenAnswer((_) async => throw Exception('waiver read failed'));
    final cubit = await atWaivers();
    await pumpStep(tester, cubit);

    expect(find.byType(FlowWaiverDocPanel), findsNothing);
    expect(find.text(staffCopy.waiverLoadFailed), findsOneWidget);
    expect(
      wizardPrimary(tester, staffCopy.retryAction).onPressed,
      isNotNull,
    );
    expect(
      wizardPrimary(tester, WizardWaiversCopy.signAction).onPressed,
      isNull,
      reason: 'nothing may be signed over a body that never arrived',
    );

    await tester.tap(find.text(staffCopy.retryAction));
    await tester.pumpAndSettle();

    verify(() => memberships.getWaiver('waiver-1', kGymId)).called(2);
    await cubit.close();
  });
}
