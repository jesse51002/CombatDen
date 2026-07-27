import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_cubit.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_outcome.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_step.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_response.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_status.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/results_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_buttons.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_result_row.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

import '../../../../bloc/membership_wizard/membership_wizard_fixtures.dart';
import 'wizard_step_harness.dart';

/// The run's one terminal screen, in each of the states a commit can leave it.
///
/// The rule the whole screen exists for: a landed breakdown is a RECEIPT and
/// outranks anything that followed it, so on a partial every row stays visible
/// and marked — the ones that worked are never dropped to make room for the
/// ones that did not.
void main() {
  late MockMemberRepository member;
  late MockMembershipsRepository memberships;
  late RecordedWizardActions recorded;

  final unlimited = plan(
    planId: 'plan-a',
    priceId: 'price-a',
    name: 'Unlimited Monthly',
  );
  final pack = plan(
    planId: 'plan-b',
    priceId: 'price-b',
    name: '5-Class Pack',
    type: PlanType.oneTime,
    price: 5000,
    classCount: 5,
  );

  setUpAll(registerWizardFallbacks);

  setUp(() {
    recorded = RecordedWizardActions();
    member = MockMemberRepository();
    memberships = MockMembershipsRepository();
    when(() => member.listMembershipPlans(any()))
        .thenAnswer((_) async => [unlimited, pack]);
    when(() => member.listGymDiscounts(any())).thenAnswer((_) async => []);
    when(() => member.getMemberDetail('m-child')).thenAnswer(
      (_) async => detail(memberId: 'm-child', firstName: 'Ella'),
    );
    when(() => memberships.listMemberWaiverStatus(any(), any()))
        .thenAnswer((_) async => []);
    when(() => member.previewStartMemberships(any())).thenAnswer(
      (_) async => startPreview(
        oneTime: invoice(total: 5000),
        dueNow: invoice(total: 8000),
        recurring: invoice(total: 8000),
      ),
    );
  });

  /// Marcus on the recurring plan, Ella on a pack, key minted, PAY not yet
  /// pressed.
  Future<MembershipWizardCubit> atPayment() async {
    final cubit = buildWizard(
      member: member,
      memberships: memberships,
      launchMember: detail(
        card: savedCard,
        authorizedToPayFor: [linked(memberId: 'm-child', firstName: 'Ella')],
      ),
      initialTrainingMemberIds: const {'m-payer', 'm-child'},
    );
    await cubit.open();
    await cubit.next();
    cubit.togglePlan(unlimited);
    await cubit.next();
    cubit.togglePlan(pack);
    await cubit.next();
    await cubit.next();
    expect(cubit.state.step, MembershipWizardStep.payment);
    return cubit;
  }

  Future<void> pumpStep(
    WidgetTester tester,
    MembershipWizardCubit cubit,
  ) =>
      pumpWizardStep(
        tester,
        cubit: cubit,
        step: WizardResultsStep(
          showAddMemberGroup: false,
          actions: recorded.actions,
        ),
      );

  testWidgets('while the charge is in flight: a spinner, a closed Done, and '
      'no way out', (tester) async {
    final gate = Completer<MemberMembershipsStartResponse>();
    when(() => member.startMemberships(any()))
        .thenAnswer((_) => gate.future);
    final cubit = await atPayment();
    unawaited(cubit.pay());
    await pumpStep(tester, cubit);

    expect(cubit.state.starting, isTrue);
    expect(find.byType(AppSpinner), findsOneWidget);
    expect(find.text(WizardResultsCopy.processingTitle), findsOneWidget);
    expect(find.byType(FlowResultRow), findsNothing);
    expect(wizardPrimary(tester, staffCopy.doneAction).onPressed, isNull);

    // No escape AT ALL — not a ghost button wired to nothing. From the moment
    // PAY is pressed the run may not be abandoned without reading what
    // happened to the money.
    expect(find.byType(FlowGhostButton), findsNothing);
    expect(find.text(staffCopy.escapeAction), findsNothing);
    expect(recorded.closed, 0);

    gate.complete(
      startResponse([resultItem(memberId: 'm-payer', planId: 'plan-a')]),
    );
    await tester.pumpAndSettle();
    await cubit.close();
  });

  testWidgets('all created: one row per membership, each opening that '
      'member\'s profile', (tester) async {
    when(() => member.startMemberships(any())).thenAnswer(
      (_) async => startResponse([
        resultItem(memberId: 'm-payer', planId: 'plan-a'),
        resultItem(
          memberId: 'm-child',
          planId: 'plan-b',
          planType: PlanType.oneTime,
        ),
      ]),
    );
    final cubit = await atPayment();
    await cubit.pay();
    await pumpStep(tester, cubit);

    expect(cubit.state.outcome, MembershipWizardOutcome.allCreated);
    expect(find.text('All 2 memberships started'), findsOneWidget);
    expect(find.byType(FlowResultRow), findsNWidgets(2));
    expect(find.text('Marcus Bell · Unlimited Monthly'), findsOneWidget);
    expect(find.text('Ella Bell · 5-Class Pack'), findsOneWidget);

    await tester.tap(
      find.bySemanticsLabel(
        WizardResultsCopy.openMemberSemantic('Ella Bell'),
      ),
    );
    await tester.pumpAndSettle();
    expect(recorded.viewedMembers, ['m-child']);

    await tester.tap(
      find.widgetWithText(FlowPrimaryButton, staffCopy.doneAction),
    );
    await tester.pumpAndSettle();
    expect(recorded.closed, 1);
    await cubit.close();
  });

  testWidgets('a PARTIAL keeps every row visible and marked, and offers the '
      'retry', (tester) async {
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
    final cubit = await atPayment();
    await cubit.pay();
    await pumpStep(tester, cubit);

    expect(cubit.state.outcome, MembershipWizardOutcome.partial);
    expect(
      find.byType(FlowResultRow),
      findsNWidgets(2),
      reason: 'a row removed from a receipt is indistinguishable from a '
          'membership nobody was told about',
    );
    expect(find.text('Marcus Bell · Unlimited Monthly'), findsOneWidget);
    expect(find.text('Ella Bell · 5-Class Pack'), findsOneWidget);
    expect(
      find.text(
        staffCopy.resultConsequence(MemberMembershipsStartStatus.created),
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        staffCopy.resultConsequence(MemberMembershipsStartStatus.failed),
      ),
      findsOneWidget,
    );
    expect(find.text(WizardResultsCopy.partialNote), findsOneWidget);
    expect(
      wizardPrimary(tester, WizardResultsCopy.retry).onPressed,
      isNotNull,
    );
    // Done keeps the quieter mirror gutter beside it.
    expect(
      find.widgetWithText(FlowOutlineButton, staffCopy.doneAction),
      findsOneWidget,
    );
    await cubit.close();
  });

  testWidgets('a commit error with no breakdown renders its own message',
      (tester) async {
    when(() => member.startMemberships(any()))
        .thenAnswer((_) async => throw Exception('billing service down'));
    final cubit = await atPayment();
    await cubit.pay();
    await pumpStep(tester, cubit);

    expect(cubit.state.commitError, MembershipWizardCommitError.failed);
    expect(find.byType(FlowResultRow), findsNothing);
    expect(find.text(WizardResultsCopy.rejectedTitle), findsOneWidget);
    expect(find.text(WizardResultsCopy.rejectedSubtitle), findsOneWidget);
    expect(find.text(WizardResultsCopy.failedTitle), findsOneWidget);
    expect(
      wizardPrimary(tester, WizardResultsCopy.backToPayment).onPressed,
      isNotNull,
    );
    await cubit.close();
  });

  testWidgets('the UNCONFIRMED latch offers no retry at all', (tester) async {
    when(() => member.startMemberships(any()))
        .thenAnswer((_) async => throw Exception('never answered'));
    final cubit = await atPayment();
    await cubit.pay();
    // The same key, pressed again — the one action that could charge twice.
    await cubit.pay();
    await pumpStep(tester, cubit);

    expect(cubit.state.commitError, MembershipWizardCommitError.unconfirmed);
    expect(find.text(WizardResultsCopy.unconfirmedTitle), findsOneWidget);
    expect(find.text(WizardResultsCopy.unconfirmedBody), findsOneWidget);
    expect(
      find.text(WizardResultsCopy.rejectedSubtitle),
      findsNothing,
      reason: 'an unconfirmed attempt may have taken money',
    );
    expect(find.text(WizardResultsCopy.backToPayment), findsNothing);
    expect(find.text(WizardResultsCopy.retry), findsNothing);

    await tester.tap(
      find.widgetWithText(FlowPrimaryButton, staffCopy.doneAction),
    );
    await tester.pumpAndSettle();
    expect(recorded.closed, 1);
    await cubit.close();
  });
}
