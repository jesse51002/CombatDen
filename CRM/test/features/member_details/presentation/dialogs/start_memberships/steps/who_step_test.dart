import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_cubit.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/who/who_load_failed.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/who_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

import '../../../../bloc/membership_wizard/membership_wizard_fixtures.dart';
import 'wizard_step_harness.dart';

/// The roster step, rendered.
///
/// The behaviours pinned here are the ones the old wizard lost: a drop is
/// never invisible (the check warns BEFORE, the notice states it after), the
/// primary counts what it carries, and — the defect this whole step exists to
/// end — a failed people-read is an ERROR with a retry rather than a spinner
/// nobody can clear.
void main() {
  late MockMemberRepository member;
  late MockMembershipsRepository memberships;
  late RecordedWizardActions recorded;

  final unlimited = plan(planId: 'plan-a', priceId: 'price-a');

  setUpAll(registerWizardFallbacks);

  setUp(() {
    recorded = RecordedWizardActions();
    member = MockMemberRepository();
    memberships = MockMembershipsRepository();
    when(() => member.listMembershipPlans(any()))
        .thenAnswer((_) async => [unlimited]);
    when(() => member.listGymDiscounts(any())).thenAnswer((_) async => []);
    when(() => member.previewStartMemberships(any()))
        .thenAnswer((_) async => startPreview(recurring: invoice()));
    when(() => memberships.listMemberWaiverStatus(any(), any()))
        .thenAnswer((_) async => []);
    for (final id in const ['m-ella', 'm-sam']) {
      when(() => member.getMemberDetail(id))
          .thenAnswer((_) async => detail(memberId: id, firstName: id));
    }
  });

  /// Marcus paying for Ella and Sam, all three ticked in.
  Future<MembershipWizardCubit> household({bool open = true}) async {
    final cubit = buildWizard(
      member: member,
      memberships: memberships,
      launchMember: detail(
        authorizedToPayFor: [
          linked(memberId: 'm-ella', firstName: 'Ella'),
          linked(memberId: 'm-sam', firstName: 'Sam'),
        ],
      ),
      initialTrainingMemberIds: const {'m-payer', 'm-ella', 'm-sam'},
    );
    if (open) await cubit.open();
    return cubit;
  }

  Future<void> pumpStep(
    WidgetTester tester,
    MembershipWizardCubit cubit,
  ) =>
      pumpWizardStep(
        tester,
        cubit: cubit,
        step: WizardWhoStep(
          showAddMemberGroup: false,
          actions: recorded.actions,
        ),
      );

  testWidgets('lists everyone the payer covers, payer first, with the '
      'payer\'s Paying pill', (tester) async {
    final cubit = await household();
    await pumpStep(tester, cubit);

    expect(find.text('Marcus Bell'), findsOneWidget);
    expect(find.text('Ella Bell'), findsOneWidget);
    expect(find.text('Sam Bell'), findsOneWidget);
    expect(find.text(staffCopy.payingPill), findsOneWidget);

    // Payer first: the fact that explains the whole screen leads it.
    final payer = tester.getTopLeft(find.text('Marcus Bell')).dy;
    expect(payer, lessThan(tester.getTopLeft(find.text('Ella Bell')).dy));
    expect(payer, lessThan(tester.getTopLeft(find.text('Sam Bell')).dy));
    await cubit.close();
  });

  testWidgets('the check warns BEFORE it is used, and only where there is '
      'work to lose', (tester) async {
    final cubit = await household();
    await cubit.next();
    cubit.togglePlan(unlimited);
    await cubit.back();
    await pumpStep(tester, cubit);

    expect(find.text(WizardWhoCopy.untickNote('Marcus')), findsOneWidget);
    expect(
      find.text(WizardWhoCopy.untickNote('Ella')),
      findsNothing,
      reason: 'a warning nobody needs teaches staff to ignore the ones that '
          'matter',
    );
    await cubit.close();
  });

  testWidgets('after an untick that dropped work, the step states what went',
      (tester) async {
    final cubit = await household();
    await cubit.next();
    cubit.togglePlan(unlimited);
    await cubit.back();
    await pumpStep(tester, cubit);

    expect(cubit.state.lastConsequence, isNull);
    // The payer's own row is the first "Getting a membership" check.
    await tester.tap(find.text(staffCopy.rosterTrainingCheck(
      firstName: 'Marcus',
      isGroup: true,
    )).first);
    await tester.pumpAndSettle();

    expect(
      find.text(
        WizardWhoCopy.untickedDrop(firstName: 'Marcus', memberships: 1),
      ),
      findsOneWidget,
      reason: 'the old wizard dropped the lineup silently',
    );
    await cubit.close();
  });

  testWidgets('the primary counts the people it carries, and closes with '
      'nobody ticked', (tester) async {
    final cubit = await household();
    await pumpStep(tester, cubit);

    expect(find.text('Continue with 3 people'), findsOneWidget);
    expect(wizardPrimary(tester, 'Continue with 3 people').onPressed,
        isNotNull);

    for (final id in const ['m-payer', 'm-ella', 'm-sam']) {
      cubit.setTraining(id, false);
    }
    await tester.pumpAndSettle();

    expect(wizardPrimary(tester, 'Continue with 0 people').onPressed, isNull);
    expect(find.text(WizardWhoCopy.needSomebody), findsOneWidget);
    await cubit.close();
  });

  testWidgets('a FAILED people-read renders the retry, never a spinner — and '
      'Try again reads again', (tester) async {
    final cubit = await household();
    when(() => member.getMemberDetail('m-payer'))
        .thenAnswer((_) async => throw Exception('connection dropped'));
    await cubit.loadPayerDetail();
    await pumpStep(tester, cubit);

    expect(
      find.byType(AppSpinner),
      findsNothing,
      reason: 'the old wizard swallowed this exception and spun forever',
    );
    expect(find.byType(WhoLoadFailed), findsOneWidget);
    expect(
      find.text(WizardWhoCopy.loadFailedTitle('Marcus Bell')),
      findsOneWidget,
    );
    expect(find.text(WizardWhoCopy.loadFailedBody), findsOneWidget);
    expect(find.text(WizardWhoCopy.loadFailedFoot), findsOneWidget);
    // The step's answering line is dropped: there is no roster to explain.
    expect(find.text(staffCopy.rosterStepSubtitle), findsNothing);

    await tester.tap(find.text(staffCopy.retryAction));
    await tester.pumpAndSettle();

    verify(() => member.getMemberDetail('m-payer')).called(2);
    expect(find.byType(WhoLoadFailed), findsOneWidget);
    await cubit.close();
  });

  testWidgets('the payer switch and the two adders fire their own host '
      'action', (tester) async {
    final cubit = await household();
    await pumpStep(tester, cubit);

    await tester.tap(find.text(WizardWhoCopy.changePayer));
    await tester.pumpAndSettle();
    await tester.tap(find.text(WizardWhoCopy.addNewTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text(WizardWhoCopy.findExistingTitle));
    await tester.pumpAndSettle();

    expect(recorded.changedPayer, 1);
    expect(recorded.addedNewMember, 1);
    expect(recorded.linkedMember, 1);
    expect(recorded.closed, 0);
    await cubit.close();
  });
}
