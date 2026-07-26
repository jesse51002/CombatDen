import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/core/state/theme_controller.dart';
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
      timezone: 'America/Chicago',
      logoUrl: null,
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

    blocTest<SettingsBloc, SettingsState>(
      'saves the timezone, then updates selectedGym and bumps the '
      'saved count (not optimistic)',
      setUp: () {
        when(
          () => repository.updateGymTimezone(
            gymId: 'gym-1',
            timezone: 'America/Denver',
          ),
        ).thenAnswer((_) async {});
      },
      build: () => SettingsBloc(repository: repository),
      act: (bloc) =>
          bloc.add(const SettingsTimezoneChanged('America/Denver')),
      expect: () => const [
        SettingsState(savingTimezone: true),
        SettingsState(savingTimezone: false, timezoneSavedCount: 1),
      ],
      verify: (_) {
        // selectedGym only updates AFTER the backend commit.
        expect(selectedGym.timezone, 'America/Denver');
        verify(
          () => repository.updateGymTimezone(
            gymId: 'gym-1',
            timezone: 'America/Denver',
          ),
        ).called(1);
      },
    );

    blocTest<SettingsBloc, SettingsState>(
      'surfaces an error and leaves selectedGym untouched when the '
      'timezone save fails',
      setUp: () {
        when(
          () => repository.updateGymTimezone(
            gymId: 'gym-1',
            timezone: 'America/Denver',
          ),
        ).thenThrow(Exception('save failed'));
      },
      build: () => SettingsBloc(repository: repository),
      act: (bloc) =>
          bloc.add(const SettingsTimezoneChanged('America/Denver')),
      expect: () => [
        const SettingsState(savingTimezone: true),
        isA<SettingsState>()
            .having((s) => s.savingTimezone, 'savingTimezone', false)
            .having((s) => s.timezoneSavedCount, 'timezoneSavedCount', 0)
            .having((s) => s.error, 'error', isNotNull),
      ],
      verify: (_) {
        // NOT optimistic: the failed save never touches selectedGym.
        expect(selectedGym.timezone, 'America/Chicago');
      },
    );

    blocTest<SettingsBloc, SettingsState>(
      'ignores a no-op timezone pick (same zone) without calling the backend',
      build: () => SettingsBloc(repository: repository),
      act: (bloc) =>
          bloc.add(const SettingsTimezoneChanged('America/Chicago')),
      expect: () => const <SettingsState>[],
      verify: (_) {
        verifyNever(
          () => repository.updateGymTimezone(
            gymId: any(named: 'gymId'),
            timezone: any(named: 'timezone'),
          ),
        );
      },
    );

    blocTest<SettingsBloc, SettingsState>(
      'saves the gym profile, then updates selectedGym and bumps the '
      'saved count (not optimistic)',
      setUp: () {
        when(
          () => repository.updateGymProfile(
            gymId: 'gym-1',
            gymName: 'New Name',
            address: '1200 W 6th St, Austin, TX 78703',
            logoUrl: 'https://cdn.combatden.net/logo.png',
          ),
        ).thenAnswer((_) async {});
      },
      build: () => SettingsBloc(repository: repository),
      act: (bloc) => bloc.add(
        const GymProfileSaveRequested(
          gymName: 'New Name',
          address: '1200 W 6th St, Austin, TX 78703',
          logoUrl: 'https://cdn.combatden.net/logo.png',
        ),
      ),
      expect: () => const [
        SettingsState(savingGymProfile: true),
        SettingsState(savingGymProfile: false, gymProfileSavedCount: 1),
      ],
      verify: (_) {
        // selectedGym only updates AFTER the backend commit.
        expect(selectedGym.gymName, 'New Name');
        expect(selectedGym.address, '1200 W 6th St, Austin, TX 78703');
        expect(selectedGym.logoUrl, 'https://cdn.combatden.net/logo.png');
        verify(
          () => repository.updateGymProfile(
            gymId: 'gym-1',
            gymName: 'New Name',
            address: '1200 W 6th St, Austin, TX 78703',
            logoUrl: 'https://cdn.combatden.net/logo.png',
          ),
        ).called(1);
      },
    );

    blocTest<SettingsBloc, SettingsState>(
      'surfaces an error and leaves selectedGym untouched when the '
      'gym profile save fails',
      setUp: () {
        when(
          () => repository.updateGymProfile(
            gymId: 'gym-1',
            gymName: 'New Name',
            address: null,
            logoUrl: null,
          ),
        ).thenThrow(Exception('save failed'));
      },
      build: () => SettingsBloc(repository: repository),
      act: (bloc) => bloc.add(
        const GymProfileSaveRequested(
          gymName: 'New Name',
          address: null,
          logoUrl: null,
        ),
      ),
      expect: () => [
        const SettingsState(savingGymProfile: true),
        isA<SettingsState>()
            .having((s) => s.savingGymProfile, 'savingGymProfile', false)
            .having((s) => s.gymProfileSavedCount, 'gymProfileSavedCount', 0)
            .having((s) => s.error, 'error', isNotNull),
      ],
      verify: (_) {
        // NOT optimistic: the failed save never touches selectedGym.
        expect(selectedGym.gymName, 'Test Gym');
        expect(selectedGym.logoUrl, isNull);
      },
    );

    blocTest<SettingsBloc, SettingsState>(
      'ignores a no-op gym profile save (unchanged name + address + logo) '
      'without calling the backend',
      build: () => SettingsBloc(repository: repository),
      act: (bloc) => bloc.add(
        const GymProfileSaveRequested(
          gymName: 'Test Gym',
          address: null,
          logoUrl: null,
        ),
      ),
      expect: () => const <SettingsState>[],
      verify: (_) {
        verifyNever(
          () => repository.updateGymProfile(
            gymId: any(named: 'gymId'),
            gymName: any(named: 'gymName'),
            address: any(named: 'address'),
            logoUrl: any(named: 'logoUrl'),
          ),
        );
      },
    );

    blocTest<SettingsBloc, SettingsState>(
      'serializes two back-to-back auto-saves (blur name, then blur '
      'address) instead of running them concurrently',
      setUp: () {
        // The name save is slow; the address save is dispatched while it is
        // still in flight. With the sequential transformer the second waits,
        // so the states never interleave and the second handler sees the
        // committed name.
        when(
          () => repository.updateGymProfile(
            gymId: 'gym-1',
            gymName: 'New Name',
            address: null,
            logoUrl: null,
          ),
        ).thenAnswer((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        when(
          () => repository.updateGymProfile(
            gymId: 'gym-1',
            gymName: 'New Name',
            address: '1200 W 6th St',
            logoUrl: null,
          ),
        ).thenAnswer((_) async {});
      },
      build: () => SettingsBloc(repository: repository),
      act: (bloc) {
        bloc.add(
          const GymProfileSaveRequested(
            gymName: 'New Name',
            address: null,
            logoUrl: null,
          ),
        );
        bloc.add(
          const GymProfileSaveRequested(
            gymName: 'New Name',
            address: '1200 W 6th St',
            logoUrl: null,
          ),
        );
      },
      wait: const Duration(milliseconds: 150),
      expect: () => const [
        SettingsState(savingGymProfile: true),
        SettingsState(savingGymProfile: false, gymProfileSavedCount: 1),
        SettingsState(savingGymProfile: true, gymProfileSavedCount: 1),
        SettingsState(savingGymProfile: false, gymProfileSavedCount: 2),
      ],
      verify: (_) {
        expect(selectedGym.gymName, 'New Name');
        expect(selectedGym.address, '1200 W 6th St');
      },
    );

    blocTest<SettingsBloc, SettingsState>(
      'clears the address (empty -> null) when only the address changed',
      setUp: () {
        // The gym starts WITH an address; the save clears it.
        selectedGym.setActiveGym(
          gymId: 'gym-1',
          displayName: 'Test Gym',
          role: EmployeeRole.owner,
          timezone: 'America/Chicago',
          address: '1200 W 6th St, Austin, TX 78703',
          logoUrl: null,
        );
        when(
          () => repository.updateGymProfile(
            gymId: 'gym-1',
            gymName: 'Test Gym',
            address: null,
            logoUrl: null,
          ),
        ).thenAnswer((_) async {});
      },
      build: () => SettingsBloc(repository: repository),
      act: (bloc) => bloc.add(
        const GymProfileSaveRequested(
          gymName: 'Test Gym',
          address: null,
          logoUrl: null,
        ),
      ),
      expect: () => const [
        SettingsState(savingGymProfile: true),
        SettingsState(savingGymProfile: false, gymProfileSavedCount: 1),
      ],
      verify: (_) {
        expect(selectedGym.address, isNull);
        verify(
          () => repository.updateGymProfile(
            gymId: 'gym-1',
            gymName: 'Test Gym',
            address: null,
            logoUrl: null,
          ),
        ).called(1);
      },
    );
  });
}
