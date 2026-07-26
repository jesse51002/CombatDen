import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/members/presentation/widgets/member_app/theme_tab/theme_preview_state.dart';
import 'package:theme_flutter/data/models/customization_style.dart';

const ThemeStyle _saved = ThemeStyle(
  id: 'SavedDesign',
  displayName: 'Saved Theme',
  celebrationImageUrl: '',
  category: 'Fighting',
);
const ThemeStyle _other = ThemeStyle(
  id: 'OtherDesign',
  displayName: 'Other Theme',
  celebrationImageUrl: '',
  category: 'Yoga',
);

void _signInWithSavedTheme({String? savedThemeDesignId = 'SavedDesign'}) {
  selectedGym.setActiveGym(
    gymId: 'gym-1',
    displayName: 'Test Gym',
    role: EmployeeRole.owner,
    timezone: 'America/Chicago',
    logoUrl: null,
    savedThemeDesignId: savedThemeDesignId,
  );
}

/// Pumps a button that runs the confirm and records what it returned, so a
/// test can drive the dialog exactly the way the tab switch and the
/// "Leave without setting" button do.
Future<List<bool>> _pumpConfirmHost(WidgetTester tester) async {
  final results = <bool>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              results.add(await confirmLeaveThemePreview(context));
            },
            child: const Text('leave'),
          ),
        ),
      ),
    ),
  );
  return results;
}

void main() {
  tearDown(selectedGym.reset);

  group('previewedDesignId / hasUnsavedThemePreview', () {
    test('the pick is what is previewed; the SAVED id is untouched by it', () {
      _signInWithSavedTheme();
      expect(previewedDesignId(), isNull); // nothing picked yet this session

      selectedGym.selectStyle(_other);

      // This pair is what the grid hands each card: the checkmark follows
      // `savedThemeDesignId`, the quiet eye follows the preview. Tapping a
      // card must never move the saved one.
      expect(selectedGym.savedThemeDesignId, 'SavedDesign');
      expect(previewedDesignId(), 'OtherDesign');
      expect(hasUnsavedThemePreview(), isTrue);
    });

    test('previewing the saved design is not an unsaved preview', () {
      _signInWithSavedTheme();
      selectedGym.selectStyle(_saved);

      expect(hasUnsavedThemePreview(), isFalse);
    });

    test('a gym with NO saved theme is unsaved the moment it previews', () {
      _signInWithSavedTheme(savedThemeDesignId: null);
      expect(hasUnsavedThemePreview(), isFalse); // nothing previewed yet

      selectedGym.selectStyle(_other);
      expect(selectedGym.savedThemeDesignId, isNull);
      expect(hasUnsavedThemePreview(), isTrue);
    });

    test('the public browser (no gym) never has an unsaved preview', () {
      selectedGym.selectStyle(_other);

      expect(selectedGym.gymId, isNull);
      expect(hasUnsavedThemePreview(), isFalse);
    });
  });

  group('savedThemeLabel', () {
    test('falls back to the raw id until the catalog resolves the name', () {
      _signInWithSavedTheme();
      expect(savedThemeLabel(), 'SavedDesign');

      selectedGym.reconcileFromCatalog(const [_other, _saved]);
      expect(savedThemeLabel(), 'Saved Theme');
    });

    test('resolves the saved row even while previewing another design', () {
      _signInWithSavedTheme();
      // A pick locks in the category, which used to short-circuit the whole
      // reconcile — the saved row must still resolve.
      selectedGym.selectStyle(_other);
      selectedGym.reconcileFromCatalog(const [_other, _saved]);

      expect(savedThemeLabel(), 'Saved Theme');
      expect(previewedDesignId(), 'OtherDesign');
    });

    test('a save promotes the picked row so the name updates at once', () {
      _signInWithSavedTheme();
      selectedGym.selectStyle(_other);
      selectedGym.updateSavedThemeDesignId(_other.id);

      expect(savedThemeLabel(), 'Other Theme');
      expect(hasUnsavedThemePreview(), isFalse);
    });
  });

  group('confirmLeaveThemePreview', () {
    testWidgets('does not prompt when the preview IS the saved theme', (
      tester,
    ) async {
      _signInWithSavedTheme();
      selectedGym.selectStyle(_saved);
      final results = await _pumpConfirmHost(tester);

      await tester.tap(find.text('leave'));
      await tester.pumpAndSettle();

      expect(find.text('Leave without setting the theme?'), findsNothing);
      expect(results, [true]); // proceeds straight through
    });

    testWidgets('does not prompt in the public browser (no gym)', (
      tester,
    ) async {
      // No setActiveGym: gymId is null, so saving is impossible and there is
      // nothing to warn about.
      selectedGym.selectStyle(_other);
      final results = await _pumpConfirmHost(tester);

      await tester.tap(find.text('leave'));
      await tester.pumpAndSettle();

      expect(find.text('Leave without setting the theme?'), findsNothing);
      expect(results, [true]);
    });

    testWidgets('prompts on an unsaved preview and names what members see', (
      tester,
    ) async {
      _signInWithSavedTheme();
      selectedGym.reconcileFromCatalog(const [_other, _saved]);
      selectedGym.selectStyle(_other);
      await _pumpConfirmHost(tester);

      await tester.tap(find.text('leave'));
      await tester.pumpAndSettle();

      expect(find.text('Leave without setting the theme?'), findsOneWidget);
      expect(
        find.textContaining('Members still see Saved Theme'),
        findsOneWidget,
      );
      expect(find.text('Leave preview'), findsOneWidget);
      expect(find.text('Keep previewing'), findsOneWidget);
    });

    testWidgets('"Keep previewing" cancels and leaves the preview alone', (
      tester,
    ) async {
      _signInWithSavedTheme();
      selectedGym.reconcileFromCatalog(const [_other, _saved]);
      selectedGym.selectStyle(_other);
      final results = await _pumpConfirmHost(tester);

      await tester.tap(find.text('leave'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep previewing'));
      await tester.pumpAndSettle();

      expect(results, [false]);
      expect(previewedDesignId(), 'OtherDesign');
    });

    testWidgets('Esc resolves to CANCEL (the non-destructive default)', (
      tester,
    ) async {
      _signInWithSavedTheme();
      selectedGym.reconcileFromCatalog(const [_other, _saved]);
      selectedGym.selectStyle(_other);
      final results = await _pumpConfirmHost(tester);

      await tester.tap(find.text('leave'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(results, [false]);
      expect(previewedDesignId(), 'OtherDesign');
    });

    testWidgets('"Leave preview" reverts the preview to the saved design', (
      tester,
    ) async {
      _signInWithSavedTheme();
      selectedGym.reconcileFromCatalog(const [_other, _saved]);
      selectedGym.selectStyle(_other);
      final results = await _pumpConfirmHost(tester);

      await tester.tap(find.text('leave'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave preview'));
      await tester.pumpAndSettle();

      expect(results, [true]);
      expect(previewedDesignId(), 'SavedDesign');
      expect(hasUnsavedThemePreview(), isFalse);
    });

    testWidgets('with nothing saved, the prompt says so and still leaves', (
      tester,
    ) async {
      _signInWithSavedTheme(savedThemeDesignId: null);
      selectedGym.selectStyle(_other);
      final results = await _pumpConfirmHost(tester);

      await tester.tap(find.text('leave'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Members still see no app theme yet'),
        findsOneWidget,
      );

      await tester.tap(find.text('Leave preview'));
      await tester.pumpAndSettle();

      expect(results, [true]);
      // Nothing saved to revert to — the preview is left as-is, which still
      // changes nothing for members.
      expect(previewedDesignId(), 'OtherDesign');
    });
  });
}
