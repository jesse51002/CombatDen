import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/settings/bloc/settings_bloc.dart';
import 'package:crm/features/settings/bloc/settings_event.dart';
import 'package:crm/features/settings/bloc/settings_state.dart';
import 'package:crm/features/settings/presentation/sections/gym_profile_save_status.dart';
import 'package:crm/features/settings/presentation/sections/gym_profile_section.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';
import 'package:crm/shared/widgets/form/image_upload_picker_field.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

const _kAddress = '1200 W 6th St, Austin, TX 78703';

/// Past the status row's 200ms cross-fade.
const fadeDone = Duration(milliseconds: 250);

/// The `TextFormField` inside the [CustomTextField] carrying [label].
Finder _fieldNamed(String label) => find.descendant(
      of: find.byWidgetPredicate(
        (w) => w is CustomTextField && w.label == label,
      ),
      matching: find.byType(TextFormField),
    );

void main() {
  late _MockSettingsBloc bloc;

  setUpAll(() {
    // The logo picker builds an ApiClient, whose base URL comes from dotenv.
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost');
    registerFallbackValue(const SettingsErrorCleared());
  });

  setUp(() {
    bloc = _MockSettingsBloc();
    when(() => bloc.state).thenReturn(const SettingsState());
    selectedGym.setActiveGym(
      gymId: 'gym-1',
      displayName: 'Test Gym',
      role: EmployeeRole.owner,
      timezone: 'America/Chicago',
      address: _kAddress,
      logoUrl: null,
    );
  });

  tearDown(() => selectedGym.reset());

  Future<void> pumpSection(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BlocProvider<SettingsBloc>.value(
              value: bloc,
              child: const GymProfileSection(),
            ),
          ),
        ),
      ),
    );
  }

  /// Drop focus the way clicking elsewhere on the page does.
  Future<void> blur(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
  }

  testWidgets('there is no Save button — the section auto-saves',
      (tester) async {
    await pumpSection(tester);

    expect(find.text('Save gym profile'), findsNothing);
    expect(find.text(kGymProfileIdleText), findsOneWidget);
  });

  testWidgets('blurring a CHANGED gym name commits it', (tester) async {
    await pumpSection(tester);

    await tester.enterText(_fieldNamed('Gym name'), 'Apex MMA');
    await blur(tester);

    verify(
      () => bloc.add(
        const GymProfileSaveRequested(
          gymName: 'Apex MMA',
          address: _kAddress,
          logoUrl: null,
        ),
      ),
    ).called(1);
  });

  testWidgets('blurring an UNCHANGED field never fires a request',
      (tester) async {
    await pumpSection(tester);

    // Focus the name, leave it alone, blur.
    await tester.tap(_fieldNamed('Gym name'));
    await tester.pump();
    await blur(tester);

    // Same for a re-typed identical value.
    await tester.enterText(_fieldNamed('Gym name'), 'Test Gym');
    await blur(tester);

    verifyNever(() => bloc.add(any()));
  });

  testWidgets(
      'a blank gym name is rejected on blur: reverts, explains, never saves',
      (tester) async {
    await pumpSection(tester);

    await tester.enterText(_fieldNamed('Gym name'), '   ');
    await blur(tester);

    final field = tester.widget<CustomTextField>(
      find.byWidgetPredicate(
        (w) => w is CustomTextField && w.label == 'Gym name',
      ),
    );
    expect(field.controller.text, 'Test Gym');
    expect(
      find.text('Gym name can\'t be empty, so we kept the last saved name.'),
      findsOneWidget,
    );
    verifyNever(() => bloc.add(any()));
  });

  testWidgets('a blank address is a real CLEAR — it sends null, never \'\'',
      (tester) async {
    await pumpSection(tester);

    await tester.enterText(_fieldNamed('Address'), '   ');
    await blur(tester);

    verify(
      () => bloc.add(
        const GymProfileSaveRequested(
          gymName: 'Test Gym',
          address: null,
          logoUrl: null,
        ),
      ),
    ).called(1);
  });

  testWidgets('picking a logo saves immediately — no blur needed',
      (tester) async {
    await pumpSection(tester);

    tester
        .widget<ImageUploadPickerField>(find.byType(ImageUploadPickerField))
        .onImageChosen('https://cdn.combatden.net/gym/logo.png');
    await tester.pump();

    verify(
      () => bloc.add(
        const GymProfileSaveRequested(
          gymName: 'Test Gym',
          address: _kAddress,
          logoUrl: 'https://cdn.combatden.net/gym/logo.png',
        ),
      ),
    ).called(1);
  });

  testWidgets('the logo previews whole (contained, 1:1) — never cropped',
      (tester) async {
    await pumpSection(tester);

    final field = tester.widget<ImageUploadPickerField>(
      find.byType(ImageUploadPickerField),
    );
    expect(field.previewFit, BoxFit.contain);
    expect(field.aspectRatio, 1);
  });

  testWidgets('shows Saving… then Saved. as the save commits', (tester) async {
    final states = StreamController<SettingsState>();
    addTearDown(states.close);
    whenListen(bloc, states.stream, initialState: const SettingsState());
    await pumpSection(tester);

    // `pumpAndSettle` can't be used here: the saving state hosts AppSpinner,
    // which animates forever. Pump past the 200ms fade instead.
    states.add(const SettingsState(savingGymProfile: true));
    await tester.pump();
    await tester.pump(fadeDone);
    expect(find.text(kGymProfileSavingText), findsOneWidget);
    expect(find.text(kGymProfileIdleText), findsNothing);

    states.add(const SettingsState(gymProfileSavedCount: 1));
    await tester.pump();
    await tester.pump(fadeDone);
    expect(find.text(kGymProfileSavedText), findsOneWidget);

    // The confirmation is transient — it fades back to the contract line.
    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pump();
    await tester.pump(fadeDone);
    expect(find.text(kGymProfileIdleText), findsOneWidget);
    expect(find.text(kGymProfileSavedText), findsNothing);
  });

  testWidgets('a failed save keeps the typed value and offers a retry',
      (tester) async {
    whenListen(
      bloc,
      Stream<SettingsState>.fromIterable(const [
        SettingsState(savingGymProfile: true),
        SettingsState(error: 'boom'),
      ]),
      initialState: const SettingsState(),
    );
    await pumpSection(tester);

    await tester.enterText(_fieldNamed('Gym name'), 'Apex MMA');
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text(kGymProfileErrorText), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    // The typed value is never discarded.
    final field = tester.widget<CustomTextField>(
      find.byWidgetPredicate(
        (w) => w is CustomTextField && w.label == 'Gym name',
      ),
    );
    expect(field.controller.text, 'Apex MMA');
  });
}
