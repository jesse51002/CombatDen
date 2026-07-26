import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/core/network/stripe_account_context.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_cubit.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_request.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_step.dart';
import 'package:crm/features/member_details/data/models/card_on_file.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/payment/payment_one_off_group.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/payment/payment_saved_card_group.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/payment_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_consent_check.dart';

import '../../../../bloc/membership_wizard/membership_wizard_fixtures.dart';
import 'wizard_step_harness.dart';

/// The settlement step, rendered.
///
/// The catalogued defect it exists to fix is the one-off card: the old wizard
/// silently IGNORED a card staff had typed in the moment the cart turned
/// recurring, so a chip sat on screen beside a charge that never touched it.
/// Here the group is blocked rather than hidden, and it states the reason.
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
    when(() => memberships.listMemberWaiverStatus(any(), any()))
        .thenAnswer((_) async => []);
    // $50.00 one-time + $80.00 due now = $130.00 settles today.
    when(() => member.previewStartMemberships(any())).thenAnswer(
      (_) async => startPreview(
        oneTime: invoice(total: 5000),
        dueNow: invoice(total: 8000),
        recurring: invoice(total: 8000),
      ),
    );
  });

  /// Marcus buying one recurring membership and one pack, standing on the
  /// payment step.
  Future<MembershipWizardCubit> atPayment({CardOnFile? card}) async {
    // A resolved connected account, so C4 (card entry down) is deterministic
    // rather than whatever the process-wide seam happens to hold.
    await stripeAccountContext.apply('acct_wizard');
    final cubit = buildWizard(
      member: member,
      memberships: memberships,
      launchMember: detail(card: card),
    );
    await cubit.open();
    await cubit.next();
    cubit.togglePlan(unlimited);
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
        step: WizardPaymentStep(
          showAddMemberGroup: false,
          actions: recorded.actions,
        ),
      );

  testWidgets('cash, the saved card and the one-off card all render',
      (tester) async {
    final cubit = await atPayment(card: savedCard);
    await pumpStep(tester, cubit);

    expect(find.text(WizardPaymentCopy.cashLabel), findsOneWidget);
    expect(find.byType(WizardPaymentSavedCardGroup), findsOneWidget);
    expect(find.text(WizardPaymentCopy.cardOnFileEyebrow), findsOneWidget);
    expect(find.byType(WizardPaymentOneOffGroup), findsOneWidget);
    expect(find.text(WizardPaymentCopy.oneOffEyebrow), findsOneWidget);
    expect(
      find.text(WizardPaymentCopy.whatPayWillDoEyebrow),
      findsOneWidget,
    );
    // The step's own answering line names the amount and states plainly that
    // nothing has moved yet.
    expect(
      find.text(WizardPaymentCopy.settlesToday('\$130.00')),
      findsOneWidget,
    );
    await cubit.close();
  });

  testWidgets('on a RECURRING cart the one-off card is blocked, not hidden — '
      'and states its reason', (tester) async {
    final cubit = await atPayment(card: savedCard);
    await pumpStep(tester, cubit);

    expect(cubit.state.oneOffCardBlock, OneOffCardBlock.cartHasRecurring);
    expect(
      find.byType(WizardPaymentOneOffGroup),
      findsOneWidget,
      reason: 'a control that vanishes teaches nobody why',
    );
    expect(find.text(WizardPaymentCopy.notUsableTag), findsOneWidget);
    expect(
      find.text(WizardPaymentCopy.oneOffBlockedByRecurring),
      findsOneWidget,
      reason: 'the old wizard ignored the captured card in silence',
    );
    // Still reachable, so the card already typed in can be seen and removed.
    expect(find.text(WizardPaymentCopy.useOneOffCard), findsOneWidget);
    await cubit.close();
  });

  testWidgets('the saved card warns that updating re-bills EVERY recurring '
      'membership the payer holds', (tester) async {
    final cubit = await atPayment(card: savedCard);
    await pumpStep(tester, cubit);

    expect(
      find.text(WizardPaymentCopy.savedCardLabel('Marcus')),
      findsOneWidget,
    );
    expect(
      find.text(WizardPaymentCopy.updateCardWarning('Marcus')),
      findsOneWidget,
    );

    await tester.tap(find.text(WizardPaymentCopy.updateCard));
    await tester.pumpAndSettle();
    expect(recorded.updatedSavedCard, 1);
    await cubit.close();
  });

  testWidgets('with no saved card and no cash the primary is closed, and '
      'cash opens it', (tester) async {
    final cubit = await atPayment();
    await pumpStep(tester, cubit);

    expect(
      find.text(WizardPaymentCopy.noSavedCard('Marcus')),
      findsOneWidget,
    );
    expect(find.text(WizardPaymentCopy.needSettlement), findsOneWidget);
    expect(wizardPrimary(tester, 'Pay \$130.00').onPressed, isNull);

    await tester.tap(
      find.widgetWithText(FlowConsentCheck, WizardPaymentCopy.cashLabel),
    );
    await tester.pumpAndSettle();

    expect(cubit.state.paidWithCash, isTrue);
    expect(wizardPrimary(tester, 'Pay \$130.00').onPressed, isNotNull);
    expect(find.text(WizardPaymentCopy.needSettlement), findsNothing);
    await cubit.close();
  });

  testWidgets('the primary carries the amount that settles today',
      (tester) async {
    final cubit = await atPayment(card: savedCard);
    await pumpStep(tester, cubit);

    expect(find.text(WizardPaymentCopy.pay('\$130.00')), findsOneWidget);
    expect(wizardPrimary(tester, 'Pay \$130.00').onPressed, isNotNull);
    // And the echo above it names the card that will actually settle.
    expect(
      find.text(WizardPaymentCopy.dueTodayOn(savedCard.lastFour)),
      findsOneWidget,
    );
    await cubit.close();
  });
}
