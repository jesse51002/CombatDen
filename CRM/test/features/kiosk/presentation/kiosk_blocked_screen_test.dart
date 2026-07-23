import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/check_in/data/models/check_in_error_code.dart';
import 'package:crm/features/check_in/data/models/check_in_warning.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_state.dart';
import 'package:crm/features/kiosk/presentation/screens/kiosk_blocked_screen.dart';

class _MockKioskFlowCubit extends MockCubit<KioskFlowState>
    implements KioskFlowCubit {}

/// The blocked screen is the member's only explanation of a refused check-in,
/// so its WHY line must name a real reason. It picks that line off the
/// backend's stable `code` (`CheckInErrorCode`) — never the free-text `detail`
/// prose — and falls back to the calm generic line for anything it doesn't
/// recognise. Every line stays blame-free and the front-desk handoff is always
/// on screen underneath.
void main() {
  const generic = 'We couldn\'t complete your check-in just now.';

  Future<void> pumpBlocked(
    WidgetTester tester,
    KioskFlowState state,
  ) async {
    final cubit = _MockKioskFlowCubit();
    whenListen(
      cubit,
      const Stream<KioskFlowState>.empty(),
      initialState: state,
    );
    addTearDown(cubit.close);
    await tester.binding.setSurfaceSize(const Size(1180, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<KioskFlowCubit>.value(
            value: cubit,
            child: const KioskBlockedScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// A failed (thrown) check-in carrying [code] — the path this covers.
  KioskFlowState failedWith(CheckInErrorCode? code) => KioskFlowState(
        view: KioskView.blocked,
        checkInFailed: true,
        checkInErrorCode: code,
      );

  // The shipped code -> copy contract, asserted line by line.
  const copyByCode = {
    CheckInErrorCode.classFull: 'This class is full.',
    CheckInErrorCode.classInactive: 'This class isn\'t running right now.',
    CheckInErrorCode.classDeleted: 'This class isn\'t running right now.',
    CheckInErrorCode.checkinNotOpen:
        'Check-in opens a little before the class starts.',
    CheckInErrorCode.occurrenceCancelled: 'This class is cancelled today.',
    CheckInErrorCode.classNotFound: 'That class isn\'t available right now.',
    CheckInErrorCode.occurrenceNotFound:
        'That class isn\'t available right now.',
  };

  for (final entry in copyByCode.entries) {
    testWidgets('${entry.key.value} shows its own reason', (tester) async {
      await pumpBlocked(tester, failedWith(entry.key));

      expect(tester.takeException(), isNull);
      expect(find.text(entry.value), findsOneWidget);
      expect(find.text(generic), findsNothing);
      // Never a bare failure: the handoff is always underneath the reason.
      expect(find.text('Let\'s sort this at the front desk'), findsOneWidget);
      expect(find.text('Okay, got it'), findsOneWidget);
    });
  }

  test('the codes resolve to five distinct member-facing lines', () {
    // Two deliberate pairs share a line (inactive/deleted, and the two
    // not-found addresses) — the rest must not collapse into each other.
    expect(copyByCode.values.toSet().length, 5);
    expect(copyByCode.values, isNot(contains(generic)));
  });

  testWidgets('an unrecognised code falls back to the generic line',
      (tester) async {
    await pumpBlocked(tester, failedWith(CheckInErrorCode.unknown));

    expect(tester.takeException(), isNull);
    expect(find.text(generic), findsOneWidget);
  });

  testWidgets('a failure with NO code (foreign 400 / 5xx / network) falls '
      'back to the generic line', (tester) async {
    await pumpBlocked(tester, failedWith(null));

    expect(tester.takeException(), isNull);
    expect(find.text(generic), findsOneWidget);
    expect(find.text('Let\'s sort this at the front desk'), findsOneWidget);
  });

  testWidgets('a gate rejection (skip_reason, HTTP 200) keeps its own copy — '
      'the code path never disturbs it', (tester) async {
    await pumpBlocked(
      tester,
      const KioskFlowState(
        view: KioskView.blocked,
        blockedReason: CheckInWarning.outOfClasses,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('You\'re out of classes on your plan.'), findsOneWidget);
    expect(find.text(generic), findsNothing);
  });
}
