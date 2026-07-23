import 'package:flutter_test/flutter_test.dart';
import 'package:theme_flutter/data/models/customization_style.dart';

import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/core/state/selected_gym.dart';

void main() {
  tearDown(() => selectedGym.reset());

  group('SelectedGym.selectStyle', () {
    test(
      'never touches the real gym identity (admin gymName stays put)',
      () {
        // Admin context: a real gym is active.
        selectedGym.setActiveGym(
          gymId: 'gym-1',
          displayName: 'Real Gym',
          role: EmployeeRole.owner,
          timezone: 'America/Chicago',
          logoUrl: null,
        );

        // Empty id keeps this test off the real ThemeRuntime singleton
        // (unregistered in a unit test) while still exercising the state
        // update — selectStyle only calls ThemeRuntime.selectDesign when
        // `style.id.isNotEmpty`.
        const style = ThemeStyle(
          id: '',
          displayName: 'Breath & Barre',
          celebrationImageUrl: '',
          category: 'Barre',
        );
        selectedGym.selectStyle(style);

        // A theme pick records the design + category for the preview...
        expect(selectedGym.designId, '');
        expect(selectedGym.themeCategory, 'Barre');
        // ...and never clobbers the real gym's identity. This is the
        // regression this test guards: a prior refactor once wrote the
        // picked theme's display name into the gym-identity field, which
        // in the ADMIN context clobbered the real gym's chrome name.
        expect(selectedGym.gymName, 'Real Gym');
      },
    );

    test('is idempotent for the same design + category', () {
      selectedGym.setActiveGym(
        gymId: 'gym-1',
        displayName: 'Real Gym',
        role: EmployeeRole.owner,
        timezone: 'America/Chicago',
        logoUrl: null,
      );
      const style = ThemeStyle(
        id: '',
        displayName: 'Breath & Barre',
        celebrationImageUrl: '',
        category: 'Barre',
      );
      selectedGym.selectStyle(style);
      selectedGym.selectStyle(style); // no-op path (early return)

      expect(selectedGym.themeCategory, 'Barre');
      expect(selectedGym.gymName, 'Real Gym');
    });
  });

  group('SelectedGym.reset', () {
    test('clears both the admin gym and the theme selection', () {
      selectedGym.setActiveGym(
        gymId: 'gym-1',
        displayName: 'Real Gym',
        role: EmployeeRole.owner,
        timezone: 'America/Chicago',
        logoUrl: null,
      );
      const style = ThemeStyle(
        id: '',
        displayName: 'Breath & Barre',
        celebrationImageUrl: '',
        category: 'Barre',
      );
      selectedGym.selectStyle(style);

      selectedGym.reset();

      expect(selectedGym.gymId, isNull);
      expect(selectedGym.gymName, isNull);
      expect(selectedGym.designId, isNull);
      expect(selectedGym.themeCategory, isNull);
    });
  });
}
