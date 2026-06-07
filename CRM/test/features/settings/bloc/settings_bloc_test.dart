import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/core/state/theme_controller.dart';
import 'package:crm/features/gym_setup/data/models/employee_role.dart';
import 'package:crm/features/settings/bloc/settings_bloc.dart';
import 'package:crm/features/settings/bloc/settings_event.dart';
import 'package:crm/features/settings/bloc/settings_state.dart';
import 'package:crm/features/settings/data/repositories/settings_repository.dart';

class _MockSettingsRepository extends Mock implements SettingsRepository {}

void main() {
  late _MockSettingsRepository repository;

  setUpAll(() {
    registerFallbackValue(ThemeMode.system);
  });

  setUp(() {
    repository = _MockSettingsRepository();
    // The bloc reads the active gym + current mode off the global singletons.
    selectedGym.setActiveGym(
      gymId: 'gym-1',
      displayName: 'Test Gym',
      role: EmployeeRole.owner,
    );
    themeController.setMode(ThemeMode.system);
  });

  tearDown(() {
    selectedGym.reset();
    themeController.setMode(ThemeMode.system);
  });

  group('SettingsBloc', () {
    blocTest<SettingsBloc, SettingsState>(
      'applies the theme optimistically and persists it on success',
      setUp: () {
        when(
          () => repository.updateMyTheme(gymId: 'gym-1', mode: ThemeMode.dark),
        ).thenAnswer((_) async {});
      },
      build: () => SettingsBloc(repository: repository),
      act: (bloc) =>
          bloc.add(const SettingsThemeModeChanged(ThemeMode.dark)),
      expect: () => const [
        SettingsState(saving: true),
        SettingsState(saving: false),
      ],
      verify: (_) {
        expect(themeController.mode, ThemeMode.dark);
        verify(
          () => repository.updateMyTheme(gymId: 'gym-1', mode: ThemeMode.dark),
        ).called(1);
      },
    );

    blocTest<SettingsBloc, SettingsState>(
      'reverts the optimistic theme and surfaces an error on failure',
      setUp: () {
        when(
          () => repository.updateMyTheme(gymId: 'gym-1', mode: ThemeMode.dark),
        ).thenThrow(Exception('save failed'));
      },
      build: () => SettingsBloc(repository: repository),
      act: (bloc) =>
          bloc.add(const SettingsThemeModeChanged(ThemeMode.dark)),
      expect: () => [
        const SettingsState(saving: true),
        isA<SettingsState>()
            .having((s) => s.saving, 'saving', false)
            .having((s) => s.error, 'error', isNotNull),
      ],
      verify: (_) {
        // Reverted back to the pre-change mode after the save failed.
        expect(themeController.mode, ThemeMode.system);
      },
    );

    blocTest<SettingsBloc, SettingsState>(
      'ignores a no-op pick (same mode) without calling the backend',
      build: () => SettingsBloc(repository: repository),
      act: (bloc) =>
          bloc.add(const SettingsThemeModeChanged(ThemeMode.system)),
      expect: () => const <SettingsState>[],
      verify: (_) {
        verifyNever(
          () => repository.updateMyTheme(
            gymId: any(named: 'gymId'),
            mode: any(named: 'mode'),
          ),
        );
      },
    );
  });
}
