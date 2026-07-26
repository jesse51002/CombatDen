import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/members/presentation/widgets/member_app/theme_tab/theme_grid.dart';
import 'package:theme_flutter/customization_service.dart';
import 'package:theme_flutter/data/models/customization_style.dart';
import 'package:theme_flutter/data/models/customization_styles_page.dart';
import 'package:theme_flutter/service_locator.dart';

class _MockThemeService extends Mock implements ThemeService {}

const ThemeStyle _savedStyle = ThemeStyle(
  id: 'SavedDesign',
  displayName: 'Saved Theme',
  celebrationImageUrl: '',
  category: 'Fighting',
);
const ThemeStyle _otherStyle = ThemeStyle(
  id: 'OtherDesign',
  displayName: 'Other Theme',
  celebrationImageUrl: '',
  category: 'Yoga',
);

void main() {
  late _MockThemeService service;

  setUp(() {
    service = _MockThemeService();
    when(
      () => service.fetchStylesPage(
        offset: any(named: 'offset'),
        limit: any(named: 'limit'),
        query: any(named: 'query'),
      ),
    ).thenAnswer(
      (_) async => const ThemeStylesPage(
        items: [_savedStyle, _otherStyle],
        total: 2,
        offset: 0,
        limit: 50,
      ),
    );
    when(() => service.activeDesignId).thenReturn('SavedDesign');
    when(() => service.selectDesign(any())).thenAnswer((_) async => true);
    getIt.registerSingleton<ThemeService>(service);
  });

  tearDown(() {
    if (getIt.isRegistered<ThemeService>()) {
      getIt.unregister<ThemeService>();
    }
    selectedGym.reset();
  });

  void signIn({String? savedThemeDesignId}) {
    selectedGym.setActiveGym(
      gymId: 'gym-1',
      displayName: 'Test Gym',
      role: EmployeeRole.owner,
      timezone: 'America/Chicago',
      logoUrl: null,
      savedThemeDesignId: savedThemeDesignId,
    );
  }

  Future<void> pumpGrid(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 800,
            child: ThemeGrid(onBackToLibrary: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('marks the SAVED design, not the one being previewed', (
    tester,
  ) async {
    signIn(savedThemeDesignId: 'SavedDesign');
    await pumpGrid(tester);

    // Previewing a DIFFERENT theme than the saved one — exactly the state
    // that used to move the checkmark onto whatever was last tapped.
    selectedGym.selectStyle(_otherStyle);
    await tester.pumpAndSettle();

    expect(find.text('Saved Theme'), findsOneWidget);
    expect(find.text('Other Theme'), findsOneWidget);

    // Exactly one checkmark, and it stays on the saved row.
    expect(find.byIcon(Symbols.check_circle_sharp), findsOneWidget);
    expect(find.text('Live for members'), findsOneWidget);
    // The tapped row says what it actually is.
    expect(find.text('Previewing only'), findsOneWidget);
    expect(find.byIcon(Symbols.visibility_sharp), findsOneWidget);
  });

  testWidgets('a save moves the checkmark onto the newly-saved design', (
    tester,
  ) async {
    signIn(savedThemeDesignId: 'SavedDesign');
    await pumpGrid(tester);
    selectedGym.selectStyle(_otherStyle);
    await tester.pumpAndSettle();

    selectedGym.updateSavedThemeDesignId('OtherDesign');
    await tester.pumpAndSettle();

    expect(find.byIcon(Symbols.check_circle_sharp), findsOneWidget);
    expect(find.text('Live for members · previewing'), findsOneWidget);
    expect(find.text('Previewing only'), findsNothing);
  });

  testWidgets('zero-state: says no theme is set, and no card is marked', (
    tester,
  ) async {
    signIn(savedThemeDesignId: null);
    await pumpGrid(tester);

    expect(find.text('Members see: '), findsOneWidget);
    expect(find.text('No app theme set yet'), findsOneWidget);
    expect(find.byIcon(Symbols.check_circle_sharp), findsNothing);
    expect(find.text('Live for members'), findsNothing);
  });

  testWidgets('the zero-state line is gone once a theme IS saved', (
    tester,
  ) async {
    signIn(savedThemeDesignId: 'SavedDesign');
    await pumpGrid(tester);

    expect(find.text('Members see: '), findsNothing);
    expect(find.text('No app theme set yet'), findsNothing);
  });

  testWidgets('the public browser gets no zero-state line and no checkmark', (
    tester,
  ) async {
    // No gym: nothing to save to, so nothing may claim to be live.
    await pumpGrid(tester);
    selectedGym.selectStyle(_otherStyle);
    await tester.pumpAndSettle();

    expect(find.text('Members see: '), findsNothing);
    expect(find.byIcon(Symbols.check_circle_sharp), findsNothing);
    expect(find.text('Previewing only'), findsOneWidget);
  });
}
