import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_cubit.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_step.dart';
import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/member_details/data/models/discount_type.dart';
import 'package:crm/features/member_details/data/models/discount_value.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/review/review_charges_failed.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/review/review_person_block.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/review_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';

import '../../../../../../shared/widgets/form/fake_network_images.dart';
import '../../../../bloc/membership_wizard/membership_wizard_fixtures.dart';
import 'wizard_step_harness.dart';

/// The review, rendered — the lineup and what it costs on ONE screen.
///
/// What is pinned here is what the old flow could not do: state both figures
/// on a reduced row, move DUE TODAY from a control that does not re-fetch, and
/// keep somebody on the list after their last membership comes off instead of
/// dropping them without a word.
///
/// The run is a parent paying for two children and buying nothing themselves —
/// the case the person block's own doc names, and the one that proves a payer
/// with no lineup is still listed.
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

  final familyPreset = DiscountResponse(
    discountId: 'disc-family',
    gymId: kGymId,
    discountName: 'Family 20%',
    discountType: DiscountType.preset,
    valueId: 'val-1',
    value: const DiscountValue(percentageOff: 20),
    createdAt: DateTime.utc(2026),
  );

  setUpAll(registerWizardFallbacks);

  setUp(() {
    recorded = RecordedWizardActions();
    member = MockMemberRepository();
    memberships = MockMembershipsRepository();
    when(() => member.listMembershipPlans(any()))
        .thenAnswer((_) async => [unlimited, pack]);
    when(() => member.listGymDiscounts(any()))
        .thenAnswer((_) async => [familyPreset]);
    when(() => member.getMemberDetail('m-child')).thenAnswer(
      (_) async => detail(memberId: 'm-child', firstName: 'Ella'),
    );
    when(() => member.getMemberDetail('m-sam')).thenAnswer(
      (_) async => detail(memberId: 'm-sam', firstName: 'Sam'),
    );
    when(() => memberships.listMemberWaiverStatus(any(), any()))
        .thenAnswer((_) async => []);
    // $50.00 one-time + $80.00 due now = $130.00 today; $80.00 each cycle.
    when(() => member.previewStartMemberships(any())).thenAnswer(
      (_) async => startPreview(
        oneTime: invoice(total: 5000),
        dueNow: invoice(total: 8000),
        recurring: invoice(total: 8000),
      ),
    );
  });

  /// Marcus paying, Ella on the recurring plan, Sam on a pack — standing on
  /// the review.
  Future<MembershipWizardCubit> atReview({bool discountElla = false}) async {
    final cubit = buildWizard(
      member: member,
      memberships: memberships,
      launchMember: detail(
        authorizedToPayFor: [
          linked(memberId: 'm-child', firstName: 'Ella'),
          linked(memberId: 'm-sam', firstName: 'Sam'),
        ],
      ),
      initialTrainingMemberIds: const {'m-child', 'm-sam'},
    );
    await cubit.open();
    await cubit.next();
    cubit.togglePlan(unlimited);
    if (discountElla) cubit.togglePresetDiscount('plan-a', 'disc-family');
    await cubit.next();
    cubit.togglePlan(pack);
    await cubit.next();
    expect(cubit.state.step, MembershipWizardStep.reviewCharges);
    return cubit;
  }

  Future<void> pumpStep(
    WidgetTester tester,
    MembershipWizardCubit cubit,
  ) =>
      pumpWizardStep(
        tester,
        cubit: cubit,
        step: WizardReviewStep(
          showAddMemberGroup: false,
          actions: recorded.actions,
        ),
      );

  Finder blockAt(int index) => find.byType(WizardReviewPersonBlock).at(index);

  testWidgets('one block per person, payer first, each listing what they are '
      'getting', (tester) async {
    await withFakeNetworkImages(() async {
      final cubit = await atReview();
      await pumpStep(tester, cubit);

      final blocks = tester
          .widgetList<WizardReviewPersonBlock>(
            find.byType(WizardReviewPersonBlock),
          )
          .toList();
      expect(
        blocks.map((block) => block.person.memberId),
        ['m-payer', 'm-child', 'm-sam'],
        reason: 'a payer buying nothing themselves is still on the list — '
            'the run bills their card either way',
      );

      expect(
        find.descendant(of: blockAt(1), matching: find.text('Unlimited '
            'Monthly')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: blockAt(2), matching: find.text('5-Class Pack')),
        findsOneWidget,
      );
      // Only the people being bought FOR carry an Edit.
      expect(find.text(staffCopy.editAction), findsNWidgets(2));
      await cubit.close();
    });
  });

  testWidgets('a discounted row states BOTH figures — the struck list price '
      'and the net', (tester) async {
    await withFakeNetworkImages(() async {
      final cubit = await atReview(discountElla: true);
      await pumpStep(tester, cubit);

      final struck =
          find.descendant(of: blockAt(1), matching: find.text('\$100.00'));
      expect(struck, findsOneWidget);
      expect(
        find.descendant(of: blockAt(1), matching: find.text('\$80.00')),
        findsOneWidget,
      );
      expect(
        tester.widget<Text>(struck).style?.decoration,
        TextDecoration.lineThrough,
        reason: 'a discount nobody can see is one the member never hears '
            'about',
      );
      // And the discount that explains the drop is named on the row.
      expect(
        find.descendant(of: blockAt(1), matching: find.text('Family 20%')),
        findsOneWidget,
      );
      await cubit.close();
    });
  });

  testWidgets('flipping the proration control moves DUE TODAY without '
      're-fetching', (tester) async {
    await withFakeNetworkImages(() async {
      final cubit = await atReview();
      await pumpStep(tester, cubit);

      expect(find.text(WizardReviewCopy.primary('\$130.00')), findsOneWidget);
      verify(() => member.previewStartMemberships(any())).called(1);

      await tester.tap(find.text(WizardReviewCopy.noChargeNow));
      await tester.pumpAndSettle();

      expect(find.text(WizardReviewCopy.primary('\$50.00')), findsOneWidget);
      verifyNever(() => member.previewStartMemberships(any()));
      await cubit.close();
    });
  });

  testWidgets('removing someone\'s LAST membership leaves them on the list '
      'and says what happened', (tester) async {
    await withFakeNetworkImages(() async {
      final cubit = await atReview();
      await pumpStep(tester, cubit);

      await tester.tap(
        find.bySemanticsLabel(
          WizardPlansCopy.removeMembership('5-Class Pack', 'Sam'),
        ),
      );
      await tester.pumpAndSettle();

      expect(cubit.state.trainingMemberIds, isNot(contains('m-sam')));
      expect(
        find.byType(WizardReviewPersonBlock),
        findsNWidgets(3),
        reason: 'nobody disappears from this list without saying so',
      );
      expect(find.text('Sam Bell'), findsOneWidget);
      expect(
        find.text(
          WizardWhoCopy.membershipRemovedDrop(
            firstName: 'Sam',
            memberships: 1,
            people: 1,
          ),
        ),
        findsOneWidget,
      );
      await cubit.close();
    });
  });

  testWidgets('Edit opens the right person\'s plans step', (tester) async {
    await withFakeNetworkImages(() async {
      final cubit = await atReview();
      await pumpStep(tester, cubit);

      await tester.tap(
        find.bySemanticsLabel(staffCopy.editSemantic('Sam Bell')),
      );
      await tester.pumpAndSettle();

      expect(cubit.state.step, MembershipWizardStep.plans);
      expect(cubit.state.currentPerson?.memberId, 'm-sam');
      expect(cubit.state.editReturnsToReview, isTrue);
      await cubit.close();
    });
  });

  testWidgets('a failed preview keeps the lineup, offers a retry and closes '
      'the primary', (tester) async {
    await withFakeNetworkImages(() async {
      when(() => member.previewStartMemberships(any()))
          .thenAnswer((_) async => throw Exception('billing timeout'));
      final cubit = await atReview();
      await pumpStep(tester, cubit);

      expect(find.byType(WizardReviewChargesFailed), findsOneWidget);
      expect(find.text(WizardReviewCopy.chargesFailedTitle), findsOneWidget);
      expect(find.text(WizardReviewCopy.chargesFailedFoot), findsOneWidget);
      expect(
        find.byType(WizardReviewPersonBlock),
        findsNWidgets(3),
        reason: 'a billing timeout must not cost staff the run they built',
      );
      expect(
        wizardPrimary(tester, WizardReviewCopy.primaryUnpriced).onPressed,
        isNull,
      );

      await tester.tap(find.text(staffCopy.retryAction));
      await tester.pumpAndSettle();
      verify(() => member.previewStartMemberships(any())).called(2);
      await cubit.close();
    });
  });
}
