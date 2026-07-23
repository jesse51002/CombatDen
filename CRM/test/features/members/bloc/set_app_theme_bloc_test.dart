import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/members/bloc/set_app_theme_bloc.dart';
import 'package:crm/features/members/bloc/set_app_theme_event.dart';
import 'package:crm/features/members/bloc/set_app_theme_state.dart';
import 'package:crm/features/members/data/gym_theme_repository.dart';

class _MockGymThemeRepository extends Mock implements GymThemeRepository {}

void main() {
  late _MockGymThemeRepository repository;

  setUp(() {
    repository = _MockGymThemeRepository();
    // The bloc reads the active gym + its saved theme off the global singleton.
    selectedGym.setActiveGym(
      gymId: 'gym-1',
      displayName: 'Test Gym',
      role: EmployeeRole.owner,
      timezone: 'America/Chicago',
      logoUrl: null,
      savedThemeDesignId: 'OldDesign',
    );
  });

  tearDown(() {
    selectedGym.reset();
  });

  group('SetAppThemeBloc', () {
    blocTest<SetAppThemeBloc, SetAppThemeState>(
      'saves the design, then updates selectedGym and bumps the saved '
      'count (not optimistic)',
      setUp: () {
        when(
          () => repository.saveGymTheme(
            gymId: 'gym-1',
            themeDesignId: 'NewDesign',
          ),
        ).thenAnswer((_) async {});
      },
      build: () => SetAppThemeBloc(repository: repository),
      act: (bloc) => bloc.add(const SetAppThemeRequested('NewDesign')),
      expect: () => const [
        SetAppThemeState(saving: true),
        SetAppThemeState(saving: false, savedCount: 1),
      ],
      verify: (_) {
        // selectedGym only updates AFTER the backend commit.
        expect(selectedGym.savedThemeDesignId, 'NewDesign');
        verify(
          () => repository.saveGymTheme(
            gymId: 'gym-1',
            themeDesignId: 'NewDesign',
          ),
        ).called(1);
      },
    );

    blocTest<SetAppThemeBloc, SetAppThemeState>(
      'surfaces an error and leaves the saved design untouched on failure',
      setUp: () {
        when(
          () => repository.saveGymTheme(
            gymId: 'gym-1',
            themeDesignId: 'NewDesign',
          ),
        ).thenThrow(Exception('save failed'));
      },
      build: () => SetAppThemeBloc(repository: repository),
      act: (bloc) => bloc.add(const SetAppThemeRequested('NewDesign')),
      expect: () => [
        const SetAppThemeState(saving: true),
        isA<SetAppThemeState>()
            .having((s) => s.saving, 'saving', false)
            .having((s) => s.savedCount, 'savedCount', 0)
            .having((s) => s.error, 'error', isNotNull),
      ],
      verify: (_) {
        // NOT optimistic: the failed save never touches selectedGym.
        expect(selectedGym.savedThemeDesignId, 'OldDesign');
      },
    );

    blocTest<SetAppThemeBloc, SetAppThemeState>(
      'ignores a no-op pick (already the saved design) without calling '
      'the backend',
      build: () => SetAppThemeBloc(repository: repository),
      act: (bloc) => bloc.add(const SetAppThemeRequested('OldDesign')),
      expect: () => const <SetAppThemeState>[],
      verify: (_) {
        verifyNever(
          () => repository.saveGymTheme(
            gymId: any(named: 'gymId'),
            themeDesignId: any(named: 'themeDesignId'),
          ),
        );
      },
    );

    blocTest<SetAppThemeBloc, SetAppThemeState>(
      'ignores an empty design id without calling the backend',
      build: () => SetAppThemeBloc(repository: repository),
      act: (bloc) => bloc.add(const SetAppThemeRequested('')),
      expect: () => const <SetAppThemeState>[],
      verify: (_) {
        verifyNever(
          () => repository.saveGymTheme(
            gymId: any(named: 'gymId'),
            themeDesignId: any(named: 'themeDesignId'),
          ),
        );
      },
    );
  });
}
