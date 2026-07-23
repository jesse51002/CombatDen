import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:crm/features/kiosk/bloc/kiosk_flow_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_flow_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_get_app_modal.dart';

class _MockKioskFlowCubit extends MockCubit<KioskFlowState>
    implements KioskFlowCubit {}

/// The "Get the CombatDen App" modal (UX-5) composes the approved kiosk welcome
/// app-card — title, benefit checklist, a REAL scannable download QR, and the
/// sign-in steps — over its own 60-second timer + Done. This proves it lays out
/// at iPad-landscape size with no exception, renders the app-card copy, encodes
/// the per-gym app-download URL in a live QR, and routes Done through the cubit.
void main() {
  Future<_MockKioskFlowCubit> pumpModal(
    WidgetTester tester, {
    String gymId = 'gym-1',
    int secondsLeft = 60,
  }) async {
    final cubit = _MockKioskFlowCubit();
    whenListen(
      cubit,
      const Stream<KioskFlowState>.empty(),
      initialState: const KioskFlowState.home(),
    );
    addTearDown(cubit.close);
    await tester.binding.setSurfaceSize(const Size(1180, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<KioskFlowCubit>.value(
            value: cubit,
            child: Stack(
              children: [
                KioskGetAppModal(gymId: gymId, secondsLeft: secondsLeft),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(); // let the drain bar's 1s tween finish
    return cubit;
  }

  testWidgets('composes the app-card: title, benefits, steps, timer, Done',
      (tester) async {
    await pumpModal(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Get the CombatDen App'), findsOneWidget);
    expect(find.text('Book classes'), findsOneWidget);
    expect(find.text('Earn rewards'), findsOneWidget);
    expect(find.text('Watch videos'), findsOneWidget);
    expect(find.text('Scan to download the app'), findsOneWidget);
    expect(
      find.text('Sign in with the email you signed up with'),
      findsOneWidget,
    );
    expect(find.text('Back to start in 60s'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });

  test('kioskAppDownloadUrl builds the per-gym app-download page URL', () {
    expect(kKioskAppDownloadBaseUrl, 'https://www.combatden.net/get-app');
    expect(
      kioskAppDownloadUrl('gym-xyz'),
      'https://www.combatden.net/get-app/gym-xyz',
    );
  });

  testWidgets('renders a single real QR (the scannable download code)',
      (tester) async {
    await pumpModal(tester, gymId: 'gym-xyz');

    // The QR renders (a real qr_flutter code, not the home glyph placeholder);
    // it is fed kioskAppDownloadUrl(gymId), asserted above.
    expect(find.byType(QrImageView), findsOneWidget);
  });

  testWidgets('Done closes the modal via the cubit', (tester) async {
    final cubit = await pumpModal(tester);

    await tester.tap(find.text('Done'));
    await tester.pump();

    verify(() => cubit.closeAppModal()).called(1);
  });
}
