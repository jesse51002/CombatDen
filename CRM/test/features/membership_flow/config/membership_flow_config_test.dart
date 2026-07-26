import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/features/membership_flow/config/kiosk_flow_copy.dart';
import 'package:crm/features/membership_flow/config/membership_flow_config.dart';
import 'package:crm/features/membership_flow/config/staff_flow_copy.dart';
import 'package:crm/features/membership_flow/discounts/discounts_capability.dart';
import 'package:crm/features/membership_flow/domain/plan_rules.dart';

/// The ONE place a surface's capability set is named.
///
/// The properties worth pinning are the ones a reader would otherwise have to
/// reconstruct from thirty widgets: what the kiosk cannot do, what the desk
/// can, and the fact that "cannot" is expressed by ABSENCE rather than by a
/// false flag.
void main() {
  MembershipPlanResponse plan(String id, PlanType type) =>
      MembershipPlanResponse(
        planId: id,
        gymId: 'gym',
        planName: id,
        imageUrl: '',
        planType: type,
        isPublic: true,
        createdAt: DateTime.utc(2026, 1, 1),
      );

  MembershipInfo held(String planId, String type, MembershipStatus status) =>
      MembershipInfo(
        planId: planId,
        planName: planId,
        planType: type,
        status: status,
        itemId: 'item-$planId',
        paidByMemberId: 'member-1',
        baseCost: 10000,
        durationAmount: 1,
        durationUnit: 'month',
        totalPrice: 10000,
        startDate: DateTime.utc(2026, 1, 1),
      );

  group('the kiosk config', () {
    final config = MembershipFlowConfig.kiosk();

    test('carries the member voice and the standing-distance ramp', () {
      expect(config.copy, isA<KioskFlowCopy>());
      expect(config.scale.formMeasure, greaterThan(0));
    });

    test('has NO discounts capability — there is no argument to pass', () {
      expect(config.discounts, isNull);
    });

    test('sells one membership at one unit', () {
      expect(config.cart.maxPlansPerPerson, 1);
      expect(config.cart.maxQuantity, 1);
      expect(config.cart.offersQuantity, isFalse);
      expect(config.cart.canPickAnotherPlan(0), isTrue);
      expect(config.cart.canPickAnotherPlan(1), isFalse);
    });

    test('masks an address, because a queue reads the screen', () {
      expect(
        config.identity.identityLine('ella@bell.family'),
        'e•••••@bell.family',
      );
      expect(config.identity.identityLine('   '), isNull);
    });

    test('runs both gates, trial first, and no notes', () {
      final gates = config.gatesFor([
        held('unlimited', 'recurring', MembershipStatus.active),
        held('two-week', 'trial', MembershipStatus.ended),
      ]);
      expect(gates, hasLength(2));
      expect(gates.first, isA<TrialOnceGate>());
      expect(gates.last, isA<RecurringHeldGate>());
      expect(config.notesFor(const []), isEmpty);
    });

    test('a repeat trial is CLOSED here', () {
      final gates = config.gatesFor([
        held('two-week', 'trial', MembershipStatus.ended),
      ]);
      final blocked = firstBlockingGate(gates, plan('anything', PlanType.trial));
      expect(blocked, isA<TrialOnceGate>());
    });
  });

  group('the admin config', () {
    final config = MembershipFlowConfig.admin(
      discounts: const DiscountsCapability(),
    );

    test('carries the staff voice and the desk ramp', () {
      expect(config.copy, isA<StaffFlowCopy>());
    });

    test('carries the discounts capability it was required to be given', () {
      expect(config.discounts, isNotNull);
    });

    test('sells as many plans and units as the sale needs', () {
      expect(config.cart.maxPlansPerPerson, isNull);
      expect(config.cart.maxQuantity, isNull);
      expect(config.cart.offersQuantity, isTrue);
      expect(config.cart.canPickAnotherPlan(7), isTrue);
      expect(config.cart.clampQuantity(0), 1);
      expect(config.cart.clampQuantity(9), 9);
    });

    test('prints the gym\'s own records in full', () {
      expect(
        config.identity.identityLine('ella@bell.family'),
        'ella@bell.family',
      );
    });

    test('a repeat trial is a NOTE here, never a gate', () {
      final memberships = [
        held('two-week', 'trial', MembershipStatus.ended),
      ];
      final gates = config.gatesFor(memberships);
      expect(gates, hasLength(1));
      expect(gates.single, isA<RecurringHeldGate>());
      expect(
        firstBlockingGate(gates, plan('two-week', PlanType.trial)),
        isNull,
        reason: 'staff grant repeat trials at a desk',
      );

      final notes = config.notesFor(memberships);
      expect(notes, hasLength(1));
      expect(notes.single.applies(plan('two-week', PlanType.trial)), isTrue);
    });

    test('the backend\'s duplicate-recurring guard still closes a plan', () {
      final gates = config.gatesFor([
        held('unlimited', 'recurring', MembershipStatus.overdue),
      ]);
      expect(
        firstBlockingGate(gates, plan('unlimited', PlanType.recurring)),
        isA<RecurringHeldGate>(),
      );
    });
  });

  test('a gate is never also a note, on either surface', () {
    final memberships = [
      held('two-week', 'trial', MembershipStatus.ended),
      held('unlimited', 'recurring', MembershipStatus.active),
    ];
    final configs = [
      MembershipFlowConfig.kiosk(),
      MembershipFlowConfig.admin(discounts: const DiscountsCapability()),
    ];
    for (final config in configs) {
      for (final gate in config.gatesFor(memberships)) {
        expect(gate, isA<PlanGate>());
        expect(gate, isNot(isA<PlanNote>()));
      }
      for (final note in config.notesFor(memberships)) {
        expect(note, isA<PlanNote>());
        expect(note, isNot(isA<PlanGate>()));
      }
    }
  });
}
