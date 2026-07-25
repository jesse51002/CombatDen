import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/schedule/presentation/screens/schedule_screen.dart';

/// Where a tap on a week-board card leads.
///
/// The load-bearing case is the PAUSED one. A paused class's card renders only
/// on this board, and for a while a front-desk or trainer tap on it did nothing
/// at all — no navigation, no message, no explanation. That card is the only
/// route staff have to a paused class's attendance and sign-up history, so an
/// inert tap hides real data behind a dead pixel.
void main() {
  group('a non-editor (front desk / trainer) always reaches the occurrence', () {
    test('on an ACTIVE class', () {
      expect(
        scheduleTapTarget(canEditSchedule: false, isActive: true),
        ScheduleTapTarget.occurrence,
      );
    });

    test('on a PAUSED class — the roster is the only place its history lives',
        () {
      expect(
        scheduleTapTarget(canEditSchedule: false, isActive: false),
        ScheduleTapTarget.occurrence,
      );
    });
  });

  group('an editor (owner / admin)', () {
    test('gets the chooser on an ACTIVE class', () {
      expect(
        scheduleTapTarget(canEditSchedule: true, isActive: true),
        ScheduleTapTarget.chooser,
      );
    });

    test('goes straight to the class editor on a PAUSED class', () {
      // Un-pausing is why a paused card renders for an editor, so there is
      // nothing to choose between.
      expect(
        scheduleTapTarget(canEditSchedule: true, isActive: false),
        ScheduleTapTarget.classEditor,
      );
    });
  });

  test('pausing a class never changes where a NON-editor lands', () {
    // Stated as an invariant rather than two cases: whatever else the board
    // does with `is_active`, it must not gate a non-editor's only destination
    // on it. Narrowing that guard is what made the tap inert.
    expect(
      scheduleTapTarget(canEditSchedule: false, isActive: false),
      scheduleTapTarget(canEditSchedule: false, isActive: true),
    );
  });
}
