import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/features/gym_setup/bloc/gym_setup_bloc.dart';
import 'package:crm/features/gym_setup/bloc/gym_setup_event.dart';
import 'package:crm/features/gym_setup/bloc/gym_setup_state.dart';
import 'package:crm/features/gym_setup/presentation/widgets/gym_name_step.dart';

class _MockGymSetupBloc extends MockBloc<GymSetupEvent, GymSetupState>
    implements GymSetupBloc {}

void main() {
  late _MockGymSetupBloc bloc;

  setUpAll(() {
    // GymSetupEvent is sealed, so the fallback is a real member of the
    // union rather than a Fake.
    registerFallbackValue(const GymSetupCheckRequested());
  });

  setUp(() {
    bloc = _MockGymSetupBloc();
    when(() => bloc.state).thenReturn(const GymSetupGymNameStep());
  });

  Future<void> pumpStep(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<GymSetupBloc>.value(
            value: bloc,
            child: const GymNameStep(),
          ),
        ),
      ),
    );
  }

  testWidgets('marks the address field optional', (tester) async {
    await pumpStep(tester);

    expect(find.text('Address'), findsOneWidget);
    expect(
      find.text('Optional. You can add it later in Settings.'),
      findsOneWidget,
    );
  });

  testWidgets('submits the typed address alongside the gym name',
      (tester) async {
    await pumpStep(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, "Enter your gym's name"),
      'Aztec MMA',
    );
    await tester.enterText(
      find.widgetWithText(
        TextFormField,
        'e.g. 1200 W 6th St, Austin, TX 78703',
      ),
      '  1200 W 6th St, Austin, TX 78703  ',
    );
    await tester.tap(find.text('Continue'));
    await tester.pump();

    verify(
      () => bloc.add(
        const GymSetupGymNameSubmitted(
          gymName: 'Aztec MMA',
          address: '1200 W 6th St, Austin, TX 78703',
        ),
      ),
    ).called(1);
  });

  testWidgets('submits a null address when the field is left blank',
      (tester) async {
    await pumpStep(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, "Enter your gym's name"),
      'Aztec MMA',
    );
    await tester.tap(find.text('Continue'));
    await tester.pump();

    verify(
      () => bloc.add(
        const GymSetupGymNameSubmitted(gymName: 'Aztec MMA'),
      ),
    ).called(1);
  });

  testWidgets('still requires the gym name', (tester) async {
    await pumpStep(tester);

    await tester.tap(find.text('Continue'));
    await tester.pump();

    expect(find.text('Gym name is required'), findsOneWidget);
    verifyNever(() => bloc.add(any()));
  });
}
