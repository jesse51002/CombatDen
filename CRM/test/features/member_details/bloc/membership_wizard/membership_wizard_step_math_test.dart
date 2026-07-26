import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_step.dart';

/// The spine, on its own. `who → plans (×N) → [waivers] → reviewCharges →
/// payment → results` is `5 + N` screens where something needs signing and
/// `4 + N` where nothing does — against the old wizard's `6 + 2N`, which put
/// one member on eight screens and three members on twelve.
void main() {
  group('the step list', () {
    test('is 5 + N when the run needs a signature', () {
      for (var people = 1; people <= 4; people++) {
        final steps = membershipWizardSteps(
          trainingPeople: people,
          hasWaivers: true,
        );
        expect(
          steps.length,
          5 + people,
          reason: '$people training people should walk ${5 + people} steps',
        );
        expect(
          steps.where((s) => s == MembershipWizardStep.plans).length,
          people,
        );
      }
    });

    test('drops to 4 + N when nothing needs signing', () {
      for (var people = 1; people <= 4; people++) {
        expect(
          membershipWizardSteps(
            trainingPeople: people,
            hasWaivers: false,
          ).length,
          4 + people,
        );
        expect(
          membershipWizardSteps(trainingPeople: people, hasWaivers: false),
          isNot(contains(MembershipWizardStep.waivers)),
        );
      }
    });

    test('is ordered who → plans → waivers → review → payment → results', () {
      expect(
        membershipWizardSteps(trainingPeople: 2, hasWaivers: true),
        const [
          MembershipWizardStep.who,
          MembershipWizardStep.plans,
          MembershipWizardStep.plans,
          MembershipWizardStep.waivers,
          MembershipWizardStep.reviewCharges,
          MembershipWizardStep.payment,
          MembershipWizardStep.results,
        ],
      );
    });

    test('never collapses below one plans entry while the roster is empty',
        () {
      // Staff are still assembling the roster; a spine with no plans entry
      // would leave the footer counting against nothing.
      expect(
        membershipWizardSteps(trainingPeople: 0, hasWaivers: false).length,
        5,
      );
    });
  });

  group('the step index', () {
    test('walks the plans entries one per person', () {
      for (var at = 0; at < 3; at++) {
        expect(
          membershipWizardStepIndex(
            step: MembershipWizardStep.plans,
            personIndex: at,
            trainingPeople: 3,
            hasWaivers: true,
          ),
          1 + at,
        );
      }
    });

    test('closes the gap the waiver step leaves when it is skipped', () {
      int indexOf(MembershipWizardStep step, {required bool waivers}) =>
          membershipWizardStepIndex(
            step: step,
            personIndex: 0,
            trainingPeople: 2,
            hasWaivers: waivers,
          );

      expect(indexOf(MembershipWizardStep.reviewCharges, waivers: true), 4);
      expect(indexOf(MembershipWizardStep.reviewCharges, waivers: false), 3);
      expect(indexOf(MembershipWizardStep.results, waivers: false), 5);
    });

    test('clamps a person index the roster no longer holds', () {
      expect(
        membershipWizardStepIndex(
          step: MembershipWizardStep.plans,
          personIndex: 9,
          trainingPeople: 2,
          hasWaivers: false,
        ),
        2,
      );
      expect(
        membershipWizardStepIndex(
          step: MembershipWizardStep.plans,
          personIndex: -1,
          trainingPeople: 2,
          hasWaivers: false,
        ),
        1,
      );
    });
  });
}
