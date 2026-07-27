import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_rail.dart';

/// The rail is SIX named stages while the run is `5 + N` screens, and that gap
/// is the point: the old indicator asserted a substep count of five against a
/// real `2N + 3` and was simply wrong for every family. The rail says which
/// STAGE; the topbar's `Step N of M` says how far through the screens.
///
/// So what has to hold is that the rail never claims a stage the run will not
/// reach, and that every step lands on the rung it belongs to whichever of the
/// four shapes the run takes.
void main() {
  group('the rungs a run draws', () {
    test('a run with no signatures owed has no waivers rung', () {
      final steps = wizardRailSteps(
        hasWaivers: false,
        showAddMemberGroup: false,
      );
      expect(steps, ['Who', 'Plans', 'Review', 'Payment', 'Done']);
    });

    test('a run that owes one gets it back, in position', () {
      final steps = wizardRailSteps(
        hasWaivers: true,
        showAddMemberGroup: false,
      );
      expect(steps, ['Who', 'Plans', 'Waivers', 'Review', 'Payment', 'Done']);
    });

    test('the add-member tail prepends an always-done rung', () {
      final steps = wizardRailSteps(
        hasWaivers: true,
        showAddMemberGroup: true,
      );
      expect(steps.first, kWizardAddedRung);
      expect(steps.length, 7);
    });
  });

  group('which rung is lit', () {
    int at(
      MembershipWizardStep step, {
      bool hasWaivers = false,
      bool showAddMemberGroup = false,
    }) =>
        wizardRailIndex(
          step,
          hasWaivers: hasWaivers,
          showAddMemberGroup: showAddMemberGroup,
        );

    test('every step maps onto its own rung, with no waivers', () {
      expect(at(MembershipWizardStep.who), 0);
      expect(at(MembershipWizardStep.plans), 1);
      expect(at(MembershipWizardStep.reviewCharges), 2);
      expect(at(MembershipWizardStep.payment), 3);
      expect(at(MembershipWizardStep.results), 4);
    });

    test('the waivers rung shifts everything after it by one', () {
      expect(at(MembershipWizardStep.waivers, hasWaivers: true), 2);
      expect(at(MembershipWizardStep.reviewCharges, hasWaivers: true), 3);
      expect(at(MembershipWizardStep.payment, hasWaivers: true), 4);
      expect(at(MembershipWizardStep.results, hasWaivers: true), 5);
    });

    test('the leading rung shifts everything by one more', () {
      expect(at(MembershipWizardStep.who, showAddMemberGroup: true), 1);
      expect(
        at(
          MembershipWizardStep.results,
          hasWaivers: true,
          showAddMemberGroup: true,
        ),
        6,
      );
    });

    test('the lit rung is always inside the rungs actually drawn', () {
      for (final hasWaivers in [false, true]) {
        for (final lead in [false, true]) {
          final steps = wizardRailSteps(
            hasWaivers: hasWaivers,
            showAddMemberGroup: lead,
          );
          for (final step in MembershipWizardStep.values) {
            // The waivers step cannot be reached by a run that owes nothing,
            // so it is the one pair the flow never produces.
            if (step == MembershipWizardStep.waivers && !hasWaivers) continue;
            final index = at(
              step,
              hasWaivers: hasWaivers,
              showAddMemberGroup: lead,
            );
            expect(index, greaterThanOrEqualTo(0));
            expect(index, lessThan(steps.length));
          }
        }
      }
    });
  });
}
