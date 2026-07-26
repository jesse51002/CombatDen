import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_rail.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_step_scaffold.dart';

/// The step rail's mapping, pinned.
///
/// `flowRailIndex` alone decides which rung a member sees lit, and getting
/// it wrong is SILENT: nothing throws, the rail just advertises progress that
/// has not happened. So every enum value is asserted by name, and both
/// templates are asserted to still be 6 solo / 7 group.
///
/// The mapping's own rule: a step still about WHO this person is shares the
/// rung they are standing on rather than adding one — the entry fork, the
/// identify search and the payer match are all that category.
void main() {
  /// Every step, and the rung it lights in each template.
  const expected = <KioskSignupStep, (int solo, int group)>{
    // Rung 0 — "You". Three screens about who this person is.
    KioskSignupStep.entry: (0, 0),
    KioskSignupStep.identify: (0, 0),
    KioskSignupStep.details: (0, 0),
    // Rung 1 — "Details", shared with the "is this you?" confirm.
    KioskSignupStep.extraDetails: (1, 1),
    KioskSignupStep.payerMatch: (1, 1),
    // Rung 2 — the roster in a group; in solo there is no People rung, so
    // these light the rung the member is heading INTO.
    KioskSignupStep.people: (2, 2),
    KioskSignupStep.personDetails: (2, 2),
    KioskSignupStep.match: (2, 2),
    KioskSignupStep.payerPick: (2, 2),
    KioskSignupStep.plans: (2, 3),
    KioskSignupStep.waivers: (3, 4),
    KioskSignupStep.card: (4, 5),
    // One act from the member's side: no rung may sit between reviewing and
    // paying, and the results receipt is the OUTCOME of paying, not a step.
    KioskSignupStep.review: (5, 6),
    KioskSignupStep.paying: (5, 6),
    KioskSignupStep.results: (5, 6),
    KioskSignupStep.declined: (5, 6),
    KioskSignupStep.welcome: (5, 6),
    // A terminal is not a step and renders no rail; the value stays in range
    // rather than throwing.
    KioskSignupStep.stop: (0, 0),
  };

  test('every step maps to a rung, and none is forgotten', () {
    expect(
      expected.keys.toSet(),
      KioskSignupStep.values.toSet(),
      reason: 'a step was added to the spine without a rail mapping — add it '
          'to `flowRailIndex` AND to this table in the same change.',
    );
  });

  test('the mapping is exactly the table above', () {
    expected.forEach((step, rungs) {
      expect(
        flowRailIndex(step, isGroup: false),
        rungs.$1,
        reason: 'solo rung for $step',
      );
      expect(
        flowRailIndex(step, isGroup: true),
        rungs.$2,
        reason: 'group rung for $step',
      );
    });
  });

  test('the templates stay 6 solo / 7 group, and every rung is reachable', () {
    expect(kFlowSoloSteps, hasLength(6));
    expect(kFlowGroupSteps, hasLength(7));
    for (final rungs in expected.values) {
      expect(rungs.$1, lessThan(kFlowSoloSteps.length));
      expect(rungs.$2, lessThan(kFlowGroupSteps.length));
    }
  });
}
